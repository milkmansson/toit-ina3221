
// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.   This also file includes derivative
// work from other authors and sources.  See accompanying documentation.

// Datasheet: https://www.ti.com/lit/ds/symlink/ina3221.pdf

// https://done.land/components/power/measuringcurrent/viashunt/ina3221/


/**
The INA3221 works a bit differently from the INA226: there is no register for
calibration values, or the 0.00512/Current_LSB formula. The INA3221 only gives
shunt voltage and bus voltage per channel; meaning the current (and power) are
calculated in software.

Key facts:
  - Shunt-voltage register LSB = 40 µV (per channel).
  - Bus-voltage register LSB = 8 mV (per channel).
  - The data in both registers are left-justified (bits 14..3 hold data);
  right-shift by 3 to get the raw code.
  - Shunt full-scale ≈ ±163.84 mV, so I(FS) = 0.16384/R(shunt) for each channel

*/

import log
import binary
import serial.device as serial
import serial.registers as registers

class Ina3221:
  /**
  Default $I2C-ADDRESS is 64 (0x40) with jumper defaults.

  Valid address values: 64 to 79 - See datasheet table 6-2.
  */
  static I2C-ADDRESS                            ::= 0x40

  /** Sets 'Power down' mode when used with $set-measure-mode. */
  static MODE-POWER-DOWN                        ::= 0b000
  /** Sets 'Shunt voltage -triggered' mode when used with $set-measure-mode. */
  static MODE-SHUNT-TRIGGERED                   ::= 0b001
  /** Sets 'Bus voltage -triggered' mode when used with $set-measure-mode. */
  static MODE-BUS-TRIGGERED                     ::= 0b010
  /** Sets 'Shunt and bus -triggered' mode when used with $set-measure-mode. */
  static MODE-SHUNT-BUS-TRIGGERED               ::= 0b011
  /** Sets 'Power-down (reserved mode)' when used with $set-measure-mode. */
  static MODE-POWER-DOWN2                       ::= 0b100
  /** Sets 'Shunt voltage -continuous' mode when used with $set-measure-mode. */
  static MODE-SHUNT-CONTINUOUS                  ::= 0b101
  /** Sets 'Bus voltage -continuous' mode when used with $set-measure-mode. */
  static MODE-BUS-CONTINUOUS                    ::= 0b110
  /** Sets 'Shunt and bus -continuous' mode when used with $set-measure-mode. */
  static MODE-SHUNT-BUS-CONTINUOUS              ::= 0b111


  /** Sampling option: (Default) - 1 sample = no averaging. */
  static AVERAGE-1-SAMPLE                       ::= 0x00
  /** Sampling option: Values averaged over 4 samples. */
  static AVERAGE-4-SAMPLES                      ::= 0x01
  /** Sampling option: Values averaged over 16 samples. */
  static AVERAGE-16-SAMPLES                     ::= 0x02
  /** Sampling option: Values averaged over 64 samples. */
  static AVERAGE-64-SAMPLES                     ::= 0x03
  /** Sampling option: Values averaged over 128 samples. */
  static AVERAGE-128-SAMPLES                    ::= 0x04
  /** Sampling option: Values averaged over 256 samples. */
  static AVERAGE-256-SAMPLES                    ::= 0x05
  /** Sampling option: Values averaged over 512 samples. */
  static AVERAGE-512-SAMPLES                    ::= 0x06
  /** Sampling option: Values averaged over 1024 samples. */
  static AVERAGE-1024-SAMPLES                   ::= 0x07

  /** Conversion time setting: 140us */
  static TIMING-140-US                          ::= 0x0000
  /** Conversion time setting: 204us */
  static TIMING-204-US                          ::= 0x0001
  /** Conversion time setting: 332us */
  static TIMING-332-US                          ::= 0x0002
  /** Conversion time setting: 588us */
  static TIMING-588-US                          ::= 0x0003
  /** Conversion time setting: 1.1ms (Default) */
  static TIMING-1100-US                         ::= 0x0004
  /** Conversion time setting: 2.116ms */
  static TIMING-2100-US                         ::= 0x0005
  /** Conversion time setting: 4.156ms */
  static TIMING-4200-US                         ::= 0x0006
  /** Conversion time setting: 8.244ms */
  static TIMING-8300-US                         ::= 0x0007

  /** LSBs used for converting register bits into actual values */
  static SHUNT-FULL-SCALE-VOLTAGE-LIMIT_        ::= 0.16384   // volts.
  static SHUNT-VOLTAGE-LSB_                     ::= 0.00004   // volts. 40 uV (per channel).
  static BUS-VOLTAGE-LSB_                       ::= 0.008     // volts, 8 mV (per channel).
  static POWER-VALID-LSB_                       ::= 0.008     // volts, 8 mV for upper and lower limits.

  /** Register list */
  static REGISTER-CONFIGURATION_                ::= 0x00   //RW  // Configuration
  static REGISTER-SHUNT-VOLTAGE-CH1_            ::= 0x01   //R   // Shunt Voltage Channel 1
  static REGISTER-BUS-VOLTAGE-CH1_              ::= 0x02   //R   // Bus Voltage Channel 1
  static REGISTER-SHUNT-VOLTAGE-CH2_            ::= 0x03   //R   // Shunt Voltage Channel 2
  static REGISTER-BUS-VOLTAGE-CH2_              ::= 0x04   //R   // Bus Voltage Channel 2
  static REGISTER-SHUNT-VOLTAGE-CH3_            ::= 0x05   //R   // Shunt Voltage Channel 3
  static REGISTER-BUS-VOLTAGE-CH3_              ::= 0x06   //R   // Bus Voltage Channel 3
  static REGISTER-CRITICAL-ALERT-LIMIT-CH1_     ::= 0x07   //RW  // Critical Alert Limit Channel 1
  static REGISTER-WARNING-ALERT-LIMIT-CH1_      ::= 0x08   //RW  // Warning Alert Limit Channel 1
  static REGISTER-CRITICAL-ALERT-LIMIT-CH2_     ::= 0x09   //RW  // Critical Alert Limit Channel 2
  static REGISTER-WARNING-ALERT-LIMIT-CH2_      ::= 0x0A   //RW  // Warning Alert Limit Channel 2
  static REGISTER-CRITICAL-ALERT-LIMIT-CH3_     ::= 0x0B   //RW  // Critical Alert Limit Channel 3
  static REGISTER-WARNING-ALERT-LIMIT-CH3_      ::= 0x0C   //RW  // Warning Alert Limit Channel 3
  static REGISTER-SHUNTVOLTAGE-SUM_             ::= 0x0D   //R   // Shunt Voltage Sum
  static REGISTER-SHUNTVOLTAGE-SUM-LIMIT_       ::= 0x0E   //RW  // Shunt Voltage Sum Limit
  static REGISTER-MASK-ENABLE_                  ::= 0x0F   //RW  // Mask/Enable
  static REGISTER-POWERVALID-UPPER-LIMIT_       ::= 0x10   //RW  // Power-Valid Upper Limit
  static REGISTER-POWERVALID-LOWER-LIMIT_       ::= 0x11   //RW  // Power-Valid Lower Limit
  static REGISTER-MANUF-ID_                     ::= 0xFE   //R   // Contains unique manufacturer identification number.
  static REGISTER-DIE-ID_                       ::= 0xFF   //R   // Contains unique die identification number

  /** Die & Manufacturer Info Masks - for use with $REGISTER-DIE-ID_ register */
  static DIE-ID-RID-MASK_                       ::= 0b00000000_00001111
  static DIE-ID-DID-MASK_                       ::= 0b11111111_11110000

  // Alert limit values are 12 bit and left justified.  Registers 0x01-0x0C,0x10,0x11
  // Only 0x01-0x06,0x10,0x11 are signed, 0x07-0x0C are not. Using this mask:
  static ALERT-LIMIT-MASK_                      ::= 0b11111111_11111000
  // Similarly for Registers 0D and 0E, left justified by 1, (and signed)
  static SUMMATION-MASK_                        ::= 0b11111111_11111110

  /** Masks for use with $REGISTER-CONFIGURATION_ register. */
  static CONF-RESET-MASK_                       ::= 0b10000000_00000000
  static CONF-CH1-ENABLE-MASK_                  ::= 0b01000000_00000000
  static CONF-CH2-ENABLE-MASK_                  ::= 0b00100000_00000000
  static CONF-CH3-ENABLE-MASK_                  ::= 0b00010000_00000000
  static CONF-AVERAGE-MASK_                     ::= 0b00001110_00000000
  static CONF-BUSVC-MASK_                       ::= 0b00000011_10000000
  static CONF-SHUNTVC-MASK_                     ::= 0b00000000_00111000
  static CONF-MODE-MASK_                        ::= 0b00000000_00000111

  /**
  Masks for use with $REGISTER-MASK-ENABLE_ register.
  */
  static ALERT-CONVERSION-READY-FLAG_           ::= 0b00000000_00000001
  static ALERT-TIMING-CONTROL-FLAG_             ::= 0b00000000_00000010
  static ALERT-POWER-VALID-FLAG_                ::= 0b00000000_00000100
  static ALERT-WARN-CH3-FLAG_                   ::= 0b00000000_00001000
  static ALERT-WARN-CH2-FLAG_                   ::= 0b00000000_00010000
  static ALERT-WARN-CH1-FLAG_                   ::= 0b00000000_00100000
  static ALERT-SUMMATION-FLAG_                  ::= 0b00000000_01000000
  static ALERT-CRITICAL-CH3-FLAG_               ::= 0b00000000_10000000
  static ALERT-CRITICAL-CH2-FLAG_               ::= 0b00000001_00000000
  static ALERT-CRITICAL-CH1-FLAG_               ::= 0b00000010_00000000
  static CRITICAL-ALERT-LATCH-FLAG_             ::= 0b00000100_00000000
  static WARNING-ALERT-LATCH-FLAG_              ::= 0b00001000_00000000
  static SUMMATION-CONTROL-CH3-FLAG_            ::= 0b00010000_00000000
  static SUMMATION-CONTROL-CH2-FLAG_            ::= 0b00100000_00000000
  static SUMMATION-CONTROL-CH1-FLAG_            ::= 0b01000000_00000000

  /** Several INA* devices use the same I2C ID.  This value for Device ID
  identifies an actual INA3221. */
  static INA3221-DEVICE-ID_                     ::= 0x0322

  reg_/registers.Registers := ?
  logger_/log.Logger := ?
  shunt-resistor_/Map := {:}
  current-LSB_/Map := {:}
  full-scale-current_/Map := {:}

  constructor
      dev/serial.Device
      --logger/log.Logger=log.default:
    logger_ = logger.with-name "ina3221"
    logger_ = logger
    reg_ = dev.registers

    dev-id := read-device-identification
    man-id := read-manufacturer-id
    dev-rev := read-device-revision

    if (dev-id != INA3221-DEVICE-ID_):
      logger_.error "Device is NOT an INA3221" --tags={ "expected-id" : INA3221-DEVICE-ID_, "received-id": dev-id }
      throw "Device is not an INA226. Expected 0x$(%04x INA3221-DEVICE-ID_) got 0x$(%04x dev-id)"

    initialize-device_

  initialize-device_ -> none:
    // Maybe not required but the manual suggests you should do it.
    reset_

    // Initialize Default sampling, conversion timing, and measuring mode.
    set-sampling-rate AVERAGE-128-SAMPLES
    set-bus-conversion-time TIMING-1100-US
    set-shunt-conversion-time TIMING-1100-US
    set-measure-mode MODE-SHUNT-BUS-CONTINUOUS

    // Set Defaults for Shunt Resistor - module usually ships with R100 (0.100 Ohm) on all three
    // channels
    set-shunt-resistor 0.100 --channel=1
    set-shunt-resistor 0.100 --channel=2
    set-shunt-resistor 0.100 --channel=3

    /*
    Performing a single measurement during initialisation assists with accuracy for first reads.
    */
    trigger-measurement --wait

  /**
  Resets Device.

  Setting bit 16 resets the device.  Once directly set, the bit self-clears
  afterwards.
  */
  reset_ -> none:
    write-register_ REGISTER-CONFIGURATION_ 1 --mask=CONF-RESET-MASK_

  /**
  Set shunt resistor value for the specified channel.
  */
  set-shunt-resistor resistor/float --channel/int -> none:
    assert: 1 <= channel <= 3
    shunt-resistor_[channel]     = resistor
    current-LSB_[channel]        = SHUNT-VOLTAGE-LSB_ / resistor
    full-scale-current_[channel] = SHUNT-FULL-SCALE-VOLTAGE-LIMIT_ / resistor

  /**
  Sets measure mode.  Use one of the 'MODE-***' statics.
  */
  set-measure-mode mode/int -> none:
    write-register_ REGISTER-CONFIGURATION_ mode --mask=CONF-MODE-MASK_

  /**
  Returns current measure mode.  Returns one of the 'MODE-***' statics.
  */
  get-measure-mode -> int:
    return read-register_ REGISTER-CONFIGURATION_ --mask=CONF-MODE-MASK_

  /**
  Sets device wide conversion-time, for bus only.

  Needs one of the 'TIMING-*-US' statics.
  */
  set-bus-conversion-time code/int -> none:
    write-register_ REGISTER-CONFIGURATION_ code --mask=CONF-BUSVC-MASK_

  /**
  Returns device wide conversion-time, for bus only.

  Returns one of the 'TIMING-*-US' statics.
  */
  get-bus-conversion-time -> int:
    return read-register_ REGISTER-CONFIGURATION_ --mask=CONF-BUSVC-MASK_

  /**
  Sets device wide conversion-time, for shunt only.

  Needs one of the 'TIMING-*-US' statics.
  */
  set-shunt-conversion-time code/int -> none:
    write-register_ REGISTER-CONFIGURATION_ code --mask=CONF-SHUNTVC-MASK_

  /**
  Returns device wide conversion-time, for shunt only.

  Returns one of the 'TIMING-*-US' statics.
  */
  get-shunt-conversion-time -> int:
    return read-register_ REGISTER-CONFIGURATION_ --mask=CONF-SHUNTVC-MASK_

  /**
  Sets device-wide sampling Rate for measurements.  See README.md
  */
  set-sampling-rate code/int -> none:
    write-register_ REGISTER-CONFIGURATION_ code --mask=CONF-AVERAGE-MASK_

  /**
  Returns device-wide sampling Rate for measurements.  See README.md
  */
  get-sampling-rate -> int:
    return read-register_ REGISTER-CONFIGURATION_ --mask=CONF-AVERAGE-MASK_

  /**
  Returns the current sampling rate (in samples, not the static).
  */
  get-sampling-rate-us -> int:
    return get-sampling-rate-from-enum get-sampling-rate

  /**
  Enables critical alert latching.  See README.md.
  */
  enable-critical-alert-latching -> none:
    write-register_ REGISTER-MASK-ENABLE_ 1 --mask=CRITICAL-ALERT-LATCH-FLAG_

  /**
  Disables critical alert latching.  See README.md.
  */
  disable-critical-alert-latching -> none:
    write-register_ REGISTER-MASK-ENABLE_ 0 --mask=CRITICAL-ALERT-LATCH-FLAG_

  /**
  Enables warning alert latching.  See README.md.
  */
  enable-warning-alert-latching -> none:
    write-register_ REGISTER-MASK-ENABLE_ 1 --mask=WARNING-ALERT-LATCH-FLAG_

  /**
  Disables warning alert latching.  See README.md.
  */
  disable-warning-alert-latching -> none:
    write-register_ REGISTER-MASK-ENABLE_ 0 --mask=WARNING-ALERT-LATCH-FLAG_

  /**
  Set the critical alert threshold (current based, in amps) for a specific channel.

  'Critical' alerts compare and assert on each conversion.  See README.md.
  */
  set-critical-alert-threshold --current/float --channel/int -> none:
    assert: 1 <= channel <= 3
    threshold-value/int := (current / current-LSB_[channel]).round
    write-register_ (REGISTER-CRITICAL-ALERT-LIMIT-CH1_ + ((channel - 1) * 2)) threshold-value --mask=ALERT-LIMIT-MASK_
    //logger_.info "set-critical-alert-threshold: current=$(%0.3f current) [volts: $(%0.3f get-critical-alert-threshold --voltage --channel=channel)]"

  /**
  Get the critical alert threshold (current based, in amps) for a specific channel.

  'Critical' alerts compare and assert on each conversion.  See README.md.
  */
  get-critical-alert-threshold --current --channel/int -> float:
    assert: 1 <= channel <= 3
    raw-read := read-register_ (REGISTER-CRITICAL-ALERT-LIMIT-CH1_ + ((channel - 1) * 2)) --mask=ALERT-LIMIT-MASK_
    return raw-read * current-LSB_[channel]

  /**
  Set the critical alert threshold (voltage based, in volts) for a specific channel.

  'Critical' alerts compare and assert on each conversion.  See README.md.
  */
  set-critical-alert-threshold --voltage/float --channel/int -> none:
    assert: 1 <= channel <= 3
    threshold-value/int := (voltage / SHUNT-VOLTAGE-LSB_).round << 3
    write-register_ (REGISTER-CRITICAL-ALERT-LIMIT-CH1_ + ((channel - 1) * 2)) threshold-value --mask=ALERT-LIMIT-MASK_
    //logger_.info "set-critical-alert-threshold: voltage=$(%0.3f voltage) [current: $(%0.3f get-critical-alert-threshold --current --channel=channel)]"

  /**
  Get the critical alert threshold (voltage based, in volts) for a specific channel.

  'Critical' alerts compare and assert on each conversion.  See README.md.
  */
  get-critical-alert-threshold --voltage --channel/int -> float:
    assert: 1 <= channel <= 3
    raw-read := read-register_ (REGISTER-CRITICAL-ALERT-LIMIT-CH1_ + ((channel - 1) * 2)) --mask=ALERT-LIMIT-MASK_
    return raw-read  * SHUNT-VOLTAGE-LSB_

  /**
  Set the warning alert threshold (current based, in amps) for a specific channel.

  'Warning' alerts     .  See README.md.
  */
  set-warning-alert-threshold --current/float --channel/int -> none:
    assert: 1 <= channel <= 3
    threshold-value/int := (current / current-LSB_[channel]).round
    if threshold-value > 4095: threshold-value = 4095
    if threshold-value < 0: threshold-value = 0
    write-register_ (REGISTER-WARNING-ALERT-LIMIT-CH1_ + ((channel - 1) * 2)) threshold-value --mask=ALERT-LIMIT-MASK_

  /**
  Get the warning alert threshold (current based, in amps) for a specific channel.

  'Warning' alerts     .  See README.md.
  */
  get-warning-alert-threshold --current --channel/int -> float:
    assert: 1 <= channel <= 3
    raw-read := read-register_ (REGISTER-WARNING-ALERT-LIMIT-CH1_ + ((channel - 1) * 2)) --mask=ALERT-LIMIT-MASK_
    return raw-read * current-LSB_[channel]

  /**
  Set the warning alert threshold (voltage based, in volts) for a specific channel.

  'Warning' alerts     .  See README.md.
  */
  set-warning-alert-threshold --voltage/float --channel/int -> none:
    assert: 1 <= channel <= 3
    threshold-value/int := (voltage / SHUNT-VOLTAGE-LSB_).round
    threshold-value = clamp-value_ threshold-value --lower=0 --upper=4095
    write-register_ (REGISTER-WARNING-ALERT-LIMIT-CH1_ + ((channel - 1) * 2)) threshold-value --mask=ALERT-LIMIT-MASK_

  /**
  Set the warning alert threshold (voltage based, in volts) for a specific channel.

  'Warning' alerts     .  See README.md.
  */
  get-warning-alert-threshold --voltage --channel/int -> float:
    assert: 1 <= channel <= 3
    raw-read := read-register_ (REGISTER-WARNING-ALERT-LIMIT-CH1_ + ((channel - 1) * 2)) --mask=ALERT-LIMIT-MASK_
    return raw-read * SHUNT-VOLTAGE-LSB_


  /**
  Sets upper limit for 'valid power' range.

  Default value for upper limit is 2710h = 10.000V.  See 'Valid power' in README.md
  */
  set-valid-power-upper-limit value/float -> none:
    raw-value := (value / POWER-VALID-LSB_).round
    //reg_.write-i16-be REGISTER-POWERVALID-UPPER-LIMIT_ raw-value
    write-register_ REGISTER-POWERVALID-UPPER-LIMIT_ raw-value --mask=ALERT-LIMIT-MASK_ --signed

  /**
  Gets configured upper limit for 'valid power' range.

  Default value for upper limit is 2710h = 10.000V.  See 'Valid power' in README.md
  */
  get-valid-power-upper-limit -> float:
    //raw-value := (reg_.read-i16-be REGISTER-POWERVALID-UPPER-LIMIT_) >> 3
    raw-value := read-register_ REGISTER-POWERVALID-UPPER-LIMIT_ --mask=ALERT-LIMIT-MASK_ --signed
    return raw-value * POWER-VALID-LSB_

  /**
  Sets lower limit for the valid power range.

  Default value for lower limit is 0x2328 = 9.0V. See README.md.
  */
  set-valid-power-lower-limit value/float -> none:
    raw-value := (value / POWER-VALID-LSB_).round << 3
    //reg_.write-i16-be REGISTER-POWERVALID-LOWER-LIMIT_ raw-value
    write-register_ REGISTER-POWERVALID-LOWER-LIMIT_ raw-value --mask=ALERT-LIMIT-MASK_ --signed

  /**
  Sets configured lower limit for the valid power range.

  Default value for lower limit is 0x2328 = 9.0V. See README.md.
  */
  get-valid-power-lower-limit -> float:
    // raw-value := (reg_.read-i16-be REGISTER-POWERVALID-LOWER-LIMIT_) >> 3
    raw-value := read-register_ REGISTER-POWERVALID-UPPER-LIMIT_ --mask=ALERT-LIMIT-MASK_ --signed
    return raw-value * POWER-VALID-LSB_

  /**
  $set-shunt-summation-limit / $get-shunt-summation-limit:

  Sets limit for the voltage of the channels marked as involved in summation.
  Both the per-channel 'Critical/Warning' limits and the 'Summation' limit
  are programmed in the register in 'shunt voltage units' not actually in amps.
  Warning compares the averaged shunt voltage (per AVG bits) and will assert accordingly.
  */
  set-shunt-summation-limit --voltage/float -> none:
    if not (current-LSB_.every: current-LSB_[it] == current-LSB_[1]):
      throw "set-summation-limit: summation invalid where shunt resistors differ."
    raw-value := (voltage / SHUNT-VOLTAGE-LSB_).round << 1
    reg_.write-i16-be REGISTER-SHUNTVOLTAGE-SUM-LIMIT_ raw-value
    //logger_.info "set-shunt-summation-limit: voltage=$(voltage) [current: $(get-shunt-summation-limit --current)]"

  get-shunt-summation-limit --voltage -> float:
    if not (current-LSB_.every: current-LSB_[it] == current-LSB_[1]):
      throw "set-summation-limit: summation invalid where shunt resistors differ."
    raw-counts := reg_.read-i16-be REGISTER-SHUNTVOLTAGE-SUM-LIMIT_
    return (raw-counts >> 1) * SHUNT-VOLTAGE-LSB_

  set-shunt-summation-limit --current/float -> none:
    if not (current-LSB_.every: current-LSB_[it] == current-LSB_[1]):
      throw "set-summation-limit: summation invalid where shunt resistors differ."
    raw-value/int := (current / current-LSB_[1]).round << 1
    reg_.write-i16-be REGISTER-SHUNTVOLTAGE-SUM-LIMIT_ raw-value

  get-shunt-summation-limit --current -> float:
    if not (current-LSB_.every: current-LSB_[it] == current-LSB_[1]):
      throw "set-summation-limit: summation invalid where shunt resistors differ."
    raw-counts := reg_.read-i16-be REGISTER-SHUNTVOLTAGE-SUM-LIMIT_
    return (raw-counts >> 1) * current-LSB_[1]

  /**
  Perform a single conversion/measurement - without waiting.

  If in any TRIGGERED mode:  Executes one measurement.
  If in any CONTINUOUS mode: Immediately refreshes data.
  */
  trigger-measurement --wait/bool=false -> none:
    // If in triggered mode, wait by default.
    should-wait/bool := false
    current-measure-mode := get-measure-mode
    if get-measure-mode == MODE-SHUNT-TRIGGERED: should-wait = true
    if get-measure-mode == MODE-BUS-TRIGGERED: should-wait = true
    if get-measure-mode == MODE-SHUNT-BUS-TRIGGERED: should-wait = true

    // Reading this mask clears the CNVR (Conversion Ready) Flag.
    mask-register-value/int   := reg_.read-u16-be REGISTER-MASK-ENABLE_

    // Rewriting the mode bits starts a conversion.
    raw := read-register_ REGISTER-CONFIGURATION_ --mask=CONF-MODE-MASK_
    write-register_ REGISTER-MASK-ENABLE_ raw --mask=CONF-MODE-MASK_

    // Wait if required. If in triggered mode, wait by default, respect switch.
    if should-wait or wait: wait-until-conversion-completed

  /**
  Waits for 'conversion-ready', with a maximum wait of $get-estimated-conversion-time-ms.
  */
  wait-until-conversion-completed --max-wait-time-ms/int=(get-estimated-conversion-time-ms) -> none:
    current-wait-time-ms/int   := 0
    sleep-interval-ms/int := 50
    while (not is-conversion-ready):
      sleep --ms=sleep-interval-ms
      current-wait-time-ms += sleep-interval-ms
      if current-wait-time-ms >= max-wait-time-ms:
        logger_.debug "wait-until-conversion-completed: max-wait-time exceeded - continuing" --tags={ "max-wait-time-ms" : max-wait-time-ms }
        break

  /**
  Returns true if conversion is still ongoing. Reading this consumes it. See README.md
  */
  is-conversion-ready -> bool:
    raw/int := read-register_ REGISTER-MASK-ENABLE_ --mask=ALERT-CONVERSION-READY-FLAG_
    return raw == 1

  /**
  $timing-control-alert

  Timing-control-alert flag indicator. Use this bit to determine if the timing
  control (TC) alert pin has been asserted through software rather than
  hardware. The bit setting corresponds to the status of the TC pin. This bit
  does not clear after it has been asserted unless the power is recycled or a
  software reset is issued. The default state for the timing control alert flag
  is high
  */
  timing-control-alert -> bool:
    value/int := read-register_ REGISTER-MASK-ENABLE_ --mask=ALERT-TIMING-CONTROL-FLAG_
    return (value == 0)

  /**
  $power-invalid-alert: Power-valid-alert flag indicator.

  This bit can be used to be able to determine if the power valid (PV) alert pin
  has been asserted through software rather than hardware.  The bit setting
  corresponds to the status of the PV pin. This bit does not clear until the
  condition that caused the alert is removed, and the PV pin has cleared.

  The PV pin = high means “power valid,” low means “invalid.” The PVF bit in
  Mask/Enable mirrors the PV status so firmware can read it. So printing
  “Valid-Power-Alert triggered” when PVF=1 is a bit confusing—PVF=1 really means
  “rails are valid”.
  */
  power-invalid-alert -> bool:
    value/int := read-register_ REGISTER-MASK-ENABLE_ --mask=ALERT-POWER-VALID-FLAG_
    return (value == 0)

  /**
  $current-warning-alert: Warning-alert flag indicator.

  These bits are asserted if the corresponding channel averaged measurement has
  exceeded the warning alert limit, resulting in the Warning alert pin being
  asserted. Read these bits to determine which channel caused the warning alert.
  The Warning Alert Flag bits clear when the Mask/Enable register is read back
  */
  current-warning-alert --channel/int -> bool:
    assert: 1 <= channel <= 3
    if channel == 1:
      return (read-register_ REGISTER-MASK-ENABLE_ --mask=ALERT-WARN-CH1-FLAG_) == 1
    if channel == 2:
      return (read-register_ REGISTER-MASK-ENABLE_ --mask=ALERT-WARN-CH2-FLAG_) == 1
    if channel == 3:
      return (read-register_ REGISTER-MASK-ENABLE_ --mask=ALERT-WARN-CH3-FLAG_) == 1
    return false

  /**
  $summation-alert: Summation-alert flag indicator.

  This bit is asserted if the Shunt Voltage Sum register exceeds the Shunt
  Voltage Sum Limit register. If the summation alert flag is asserted, the
  Critical alert pin is also asserted. The Summation Alert Flag bit is cleared
  when the Mask/Enable register is read back.
  */
  summation-alert -> bool:
    value/int := read-register_ REGISTER-MASK-ENABLE_ --mask=ALERT-SUMMATION-FLAG_
    return value == 1

  /**
  $critical-alert: Critical alert flag indicator.

  Critical-alert flag indicator. These bits are asserted if the corresponding
  channel measurement has exceeded the critical alert limit resulting in the
  Critical alert pin being asserted. Read these bits to determine which channel
  caused the critical alert. The critical alert flag bits are cleared when the
  Mask/Enable register is read back.
  */
  critical-alert --channel/int -> bool:
    assert: 1 <= channel <= 3
    if channel == 1:
      return (read-register_ REGISTER-MASK-ENABLE_ --mask=ALERT-CRITICAL-CH1-FLAG_) == 1
    if channel == 2:
      return (read-register_ REGISTER-MASK-ENABLE_ --mask=ALERT-CRITICAL-CH2-FLAG_) == 1
    if channel == 3:
      return (read-register_ REGISTER-MASK-ENABLE_ --mask=ALERT-CRITICAL-CH3-FLAG_) == 1
    return false

  /**
  Clears alerts flags.
  */
  clear-alert -> none:
    register/int := read-register_ REGISTER-MASK-ENABLE_

  /**
  Enables the specified channel.
  */
  enable-channel --channel/int -> none:
    assert: 1 <= channel <= 3
    if channel == 1:
      write-register_ REGISTER-CONFIGURATION_ 1 --mask=CONF-CH1-ENABLE-MASK_
    else if channel == 2:
      write-register_ REGISTER-CONFIGURATION_ 1 --mask=CONF-CH2-ENABLE-MASK_
    else if channel == 3:
      write-register_ REGISTER-CONFIGURATION_ 1 --mask=CONF-CH3-ENABLE-MASK_

  /**
  Disables the specified channel.
  */
  disable-channel --channel/int -> none:
    assert: 1 <= channel <= 3
    if channel == 1:
      write-register_ REGISTER-CONFIGURATION_ 0 --mask=CONF-CH1-ENABLE-MASK_
    else if channel == 2:
      write-register_ REGISTER-CONFIGURATION_ 0 --mask=CONF-CH2-ENABLE-MASK_
    else if channel == 3:
      write-register_ REGISTER-CONFIGURATION_ 0 --mask=CONF-CH3-ENABLE-MASK_

  /**
  Returns a count of the enamed channels.
  */
  enabled-channel-count -> int:
    out := 0
    out += read-register_ REGISTER-CONFIGURATION_ --mask=CONF-CH1-ENABLE-MASK_
    out += read-register_ REGISTER-CONFIGURATION_ --mask=CONF-CH2-ENABLE-MASK_
    out += read-register_ REGISTER-CONFIGURATION_ --mask=CONF-CH3-ENABLE-MASK_
    return out

  /**
  Returns true if the channel is enabled.
  */
  channel-enabled --channel/int -> bool:
    assert: 1 <= channel <= 3
    if channel == 1:
      return (read-register_ REGISTER-CONFIGURATION_ --mask=CONF-CH1-ENABLE-MASK_) == 1
    if channel == 2:
      return (read-register_ REGISTER-CONFIGURATION_ --mask=CONF-CH2-ENABLE-MASK_) == 1
    if channel == 3:
      return (read-register_ REGISTER-CONFIGURATION_ --mask=CONF-CH3-ENABLE-MASK_) == 1
    return false

  /**
  Enable summation for the specified channel.
  */
  enable-summation --channel/int -> none:
    assert: 1 <= channel <= 3
    if channel == 1:
      write-register_ REGISTER-MASK-ENABLE_ 1 --mask=SUMMATION-CONTROL-CH1-FLAG_
    else if channel == 2:
      write-register_ REGISTER-MASK-ENABLE_ 1 --mask=SUMMATION-CONTROL-CH2-FLAG_
    else if channel == 3:
      write-register_ REGISTER-MASK-ENABLE_ 1 --mask=SUMMATION-CONTROL-CH3-FLAG_

  /**
  Disable summation for the specified channel.
  */
  disable-summation --channel/int -> none:
    assert: 1 <= channel <= 3
    if channel == 1:
      write-register_ REGISTER-MASK-ENABLE_ 0 --mask=SUMMATION-CONTROL-CH1-FLAG_
    else if channel == 2:
      write-register_ REGISTER-MASK-ENABLE_ 0 --mask=SUMMATION-CONTROL-CH2-FLAG_
    else if channel == 3:
      write-register_ REGISTER-MASK-ENABLE_ 0 --mask=SUMMATION-CONTROL-CH3-FLAG_





























  /**
  Returns true if the specified channel has summation enabled.
  */
  channel-summation-enabled --channel/int -> bool:
    assert: 1 <= channel <= 3
    if channel == 1:
      return (read-register_ REGISTER-MASK-ENABLE_ --mask=SUMMATION-CONTROL-CH1-FLAG_) == 1
    if channel == 2:
      return (read-register_ REGISTER-MASK-ENABLE_ --mask=SUMMATION-CONTROL-CH2-FLAG_) == 1
    if channel == 3:
      return (read-register_ REGISTER-MASK-ENABLE_ --mask=SUMMATION-CONTROL-CH3-FLAG_) == 1
    return false

  /**
  Returns shunt voltage measurement for each channel.
  */
  read-shunt-voltage --channel/int -> float?:
    if (channel < 1) or (channel > 3) : return null
    if not channel-enabled --channel=channel: return null
    raw-shunt-counts := read-register_ (REGISTER-SHUNT-VOLTAGE-CH1_ + ((channel - 1) * 2)) --mask=ALERT-LIMIT-MASK_ --signed
    return  raw-shunt-counts * SHUNT-VOLTAGE-LSB_

  /**
  Returns bus voltage measurement for each channel.
  */
  read-bus-voltage --channel/int -> float?:
    if (channel < 1) or (channel > 3) : return null
    if not channel-enabled --channel=channel: return null
    raw-bus-counts := read-register_ (REGISTER-BUS-VOLTAGE-CH1_ + ((channel - 1) * 2)) --mask=ALERT-LIMIT-MASK_ --signed
    return  raw-bus-counts * BUS-VOLTAGE-LSB_

  /**
  Returns shunt current measurement for each channel.
  */
  read-shunt-current --channel/int -> float?:
    if (channel < 1) or (channel > 3) : return null
    if not channel-enabled --channel=channel: return null
    raw-shunt-counts := read-register_ (REGISTER-BUS-VOLTAGE-CH1_ + ((channel - 1) * 2)) --mask=ALERT-LIMIT-MASK_ --signed
    return raw-shunt-counts * current-LSB_[channel]

  /**
  Returns power measurement for each channel.
  */
  read-power --channel/int -> float?:
    if (channel < 1) or (channel > 3) : return null
    if not channel-enabled --channel=channel: return null
    bus-voltage := read-bus-voltage --channel=channel
    shunt-current := read-shunt-current --channel=channel
    if (bus-voltage == null) or (shunt-current == null): return null
    return bus-voltage * shunt-current

  /**
  Returns supply voltag for each channel.  See README.md
  */
  read-supply-voltage --channel/int -> float?:
    if (channel < 1) or (channel > 3) : return null
    if not channel-enabled --channel=channel: return null
    return (read-bus-voltage --channel=channel) + (read-shunt-voltage --channel=channel)

  /**
  Returns summed shunt voltage across channels (voltage).  See README.md
  */
  read-shunt-summation --voltage -> float:
    if not (current-LSB_.every: current-LSB_[it] == current-LSB_[1]):
      throw "read-shunt-summation: summation invalid where shunt resistors differ."
    raw-counts := read-register_ REGISTER-SHUNTVOLTAGE-SUM_ --mask=SUMMATION-MASK_ --signed
    return raw-counts * SHUNT-VOLTAGE-LSB_

  /**
  Returns summed shunt voltage across channels (current).  See README.md
  */
  read-shunt-summation --current -> float:
    if not (current-LSB_.every: current-LSB_[it] == current-LSB_[1]):
      throw "read-shunt-summation: summation invalid where shunt resistors differ."
    raw-counts := read-register_ REGISTER-SHUNTVOLTAGE-SUM_ --mask=SUMMATION-MASK_ --signed
    return raw-counts * current-LSB_[1]

  /**
  Estimates a worst-case maximum waiting time based on the configuration.

  Done this way to prevent setting a global maxWait type value, to then have it fail based
  on times that are longer due to timing configurations.  Calculation also includes a 10% guard.
  */
  get-estimated-conversion-time-ms -> int:
    // Read config and decode fields
    mode/int                          := get-measure-mode
    sampling-rate/int                 := get-sampling-rate-from-enum get-sampling-rate
    bus-conversion-time/int           := get-conversion-time-us-from-enum get-bus-conversion-time
    shunt-conversion-time/int         := get-conversion-time-us-from-enum get-shunt-conversion-time

    time-contribution-us/int := 0
    if (mode & 0b001) != 0:  time-contribution-us += shunt-conversion-time  // shunt enabled mask = 0b001
    if (mode & 0b010) != 0:  time-contribution-us += bus-conversion-time    // bus enabled mask   = 0b010
    //if (mode & 0b100) != 0:  time-contribution += bus-conversion-time     // continuous mask    = 0b100

    // Essentially 3 profiles: Off, Triggered, and Continuous. BUS+/SHUNT voltage consumptions are not given
    total-us/int    := time-contribution-us * sampling-rate * enabled-channel-count

    // Add a small guard factor (~10%) to be conservative.
    total-us = ((total-us * 11.0) / 10.0).round

    // Return milliseconds, minimum 1 ms
    total-ms := ((total-us + 999) / 1000)  // Ceiling.
    if total-ms < 1: total-ms = 1

    //logger_.debug "get-estimated-conversion-time-ms is: $(total-ms)ms"
    return total-ms

  /**
  Returns a us value for 'TIMING-*-US' statics.
  */
  get-conversion-time-us-from-enum code/int -> int:
    assert: 0 <= code <= 7
    if code == TIMING-140-US:  return 140
    if code == TIMING-204-US:  return 204
    if code == TIMING-332-US:  return 332
    if code == TIMING-588-US:  return 588
    if code == TIMING-1100-US: return 1100
    if code == TIMING-2100-US: return 2100
    if code == TIMING-4200-US: return 4200
    if code == TIMING-8300-US: return 8300
    return 1100  // default/defensive - should never happen

  /**
  Returns actual number of samples count for 'AVERAGE-**-SAMPLE' statics.
  */
  get-sampling-rate-from-enum code/int -> int:
    assert: 0 <= code <= 7
    if code == AVERAGE-1-SAMPLE:     return 1
    if code == AVERAGE-4-SAMPLES:    return 4
    if code == AVERAGE-16-SAMPLES:   return 16
    if code == AVERAGE-64-SAMPLES:   return 64
    if code == AVERAGE-128-SAMPLES:  return 128
    if code == AVERAGE-256-SAMPLES:  return 256
    if code == AVERAGE-512-SAMPLES:  return 512
    if code == AVERAGE-1024-SAMPLES: return 1024
    return 1  // default/defensive - should never happen

  /**
  Reads the given register with the supplied mask.

  Given that register reads are largely similar, implemented here.  If the mask
  is left at 0xFFFF (and offset remains at 0x0), it is a read from the whole
  register.
  */
  read-register_
      register/int
      --mask/int=0xFFFF
      --offset/int=(mask.count-trailing-zeros)
      --signed/bool=false
      -> any:
    register-value/int := 0
    if signed:
      register-value = reg_.read-i16-be register
    else:
      register-value = reg_.read-u16-be register
    if mask == 0xFFFF and offset == 0:
      return register-value
    else:
      masked-value := (register-value & mask) >> offset
      return masked-value

  /**
  Writes the given register with the supplied mask.

  Given that register reads are largely similar, implemented here.  If the mask
  is left at 0xFFFF (and offset remains at 0x0) it is a write to the whole
  register.
  */
  write-register_
      register/int
      value/any
      --mask/int=0xFFFF
      --offset/int=(mask.count-trailing-zeros)
      --signed/bool=false
      -> none:
    // find allowed value range within field
    max/int := mask >> offset
    // check the value fits the field
    assert: ((value & ~max) == 0)

    if (mask == 0xFFFF) and (offset == 0):
      if signed:
        reg_.write-i16-be register (value & 0xFFFF)
      else:
        reg_.write-u16-be register (value & 0xFFFF)
    else:
      new-value/int := reg_.read-u16-be register
      new-value     &= ~mask
      new-value     |= (value << offset)
      if signed:
        reg_.write-i16-be register new-value
      else:
        reg_.write-u16-be register new-value

  /**
  Get Manufacturer ID.
  */
  read-manufacturer-id -> int:
    return reg_.read-u16-be REGISTER-MANUF-ID_

  /**
  Returns device ID.
  */
  read-device-identification -> int:
    return read-register_ REGISTER-DIE-ID_ --mask=DIE-ID-DID-MASK_

  /**
  Returns chip die revision ID.
  */
  read-device-revision -> int:
    return read-register_ REGISTER-DIE-ID_ --mask=DIE-ID-RID-MASK_

  /**
  Clamps the supplied value to specified limit.
  */
  clamp-value_ value/any --upper/any?=null --lower/any?=null -> any:
    if upper != null: if value > upper:  return upper
    if lower != null: if value < lower:  return lower
    return value

  /**
  Displays bitmasks nicely for use when testing/troubleshooting.
  */
  bits-16_ x/int --min-display-bits/int=0 -> string:
    if (x > 255) or (min-display-bits > 8):
      out-string := "$(%b x)"
      out-string = out-string.pad --left 16 '0'
      out-string = "$(out-string[0..4]).$(out-string[4..8]).$(out-string[8..12]).$(out-string[12..16])"
      return out-string
    else if (x > 15) or (min-display-bits > 4):
      out-string := "$(%b x)"
      out-string = out-string.pad --left 8 '0'
      out-string = "$(out-string[0..4]).$(out-string[4..8])"
      return out-string
    else:
      out-string := "$(%b x)"
      out-string = out-string.pad --left 4 '0'
      out-string = "$(out-string[0..4])"
      return out-string
