
// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.   This also file includes derivative 
// work from other authors and sources.  See accompanying documentation.

// Datasheet: https://www.ti.com/lit/ds/symlink/ina3221.pdf

// https://done.land/components/power/measuringcurrent/viashunt/ina3221/


/**
The INA3221 works a bit differently from the INA226: there is no register for calibration values, or 
the 0.00512/Current_LSB formula. The INA3221 only gives shunt voltage and bus voltage per channel;
meaning the current (and power) are calculated in software.

Key facts:
  - Shunt-voltage register LSB = 40 µV (per channel).
  - Bus-voltage register LSB = 8 mV (per channel).
  - The data in both registers are left-justified (bits 14..3 hold data); right-shift by 3 to get the raw code.
  - Shunt full-scale ≈ ±163.84 mV, so I(FS) = 0.16384/R(shunt) for each channel

*/

import log
import binary
import serial.device as serial
import serial.registers as registers

class Ina3221:
  /**
  Default $I2C-ADDRESS is 64 (0x40) with jumper defaults.
  
  Valid address values: 64 to 79 - See datasheet table 6-2
  */
  static I2C-ADDRESS                     ::= 0x40

  /** 
  MODE constants to be used by users during configuration with set-measure-mode
  */
  static MODE-POWER-DOWN                        ::= 0b000       // Power-down
  static MODE-SHUNT-TRIGGERED                   ::= 0b001       // Shunt voltage- triggered
  static MODE-BUS-TRIGGERED                     ::= 0b010       // Bus voltage  - triggered
  static MODE-SHUNT-BUS-TRIGGERED               ::= 0b011       // Shunt and bus- triggered
  static MODE-POWER-DOWN2                       ::= 0b100       // Power-down (reserved mode)
  static MODE-SHUNT-CONTINUOUS                  ::= 0b101       // Shunt voltage- continuous
  static MODE-BUS-CONTINUOUS                    ::= 0b110       // Bus voltage  - continuous
  static MODE-SHUNT-BUS-CONTINUOUS              ::= 0b111       // Shunt and bus- continuous

  static SHUNT-FULL-SCALE-VOLTAGE-LIMIT_/float  ::= 0.16384   // volts.
  static SHUNT-VOLTAGE-LSB_                     ::= 0.00004   // volts. 40 uV (per channel).
  static BUS-VOLTAGE-LSB_                       ::= 0.008     // volts, 8 mV (per channel).
  static POWER-VALID-LSB_                       ::= 0.008     // volts, 8 mV for upper and lower limits.


  /** 
  Sampling options used for measurements. To be used with set-sampling-rate.
  Represents the number of samples that will be averaged for each measurement.
  */
  static AVERAGE-1-SAMPLE                       ::= 0x00       // Chip Default - Values averaged over 1 sample.
  static AVERAGE-4-SAMPLES                      ::= 0x01       // Values averaged over 4 samples.
  static AVERAGE-16-SAMPLES                     ::= 0x02       // Values averaged over 16 samples.
  static AVERAGE-64-SAMPLES                     ::= 0x03       // Values averaged over 64 samples.
  static AVERAGE-128-SAMPLES                    ::= 0x04       // Values averaged over 128 samples.
  static AVERAGE-256-SAMPLES                    ::= 0x05       // Values averaged over 256 samples.
  static AVERAGE-512-SAMPLES                    ::= 0x06       // Values averaged over 512 samples.
  static AVERAGE-1024-SAMPLES                   ::= 0x07       // Values averaged over 1024 samples.

  /** 
  Bus and Shunt conversion timing options. 
  
  To be used with set-bus-conversion-time and set-shunt-conversion-time
  */
  static TIMING-140-US                          ::= 0x00       // Conversion time: 140us exactly.
  static TIMING-204-US                          ::= 0x01       // Conversion time: 204us exactly.
  static TIMING-332-US                          ::= 0x02       // Conversion time: 332us exactly.
  static TIMING-588-US                          ::= 0x03       // Conversion time: 588us exactly.
  static TIMING-1100-US                         ::= 0x04       // Chip Default. Conversion time: 1.1ms exactly.
  static TIMING-2100-US                         ::= 0x05       // Conversion time: 2.116ms exactly.
  static TIMING-4200-US                         ::= 0x06       // Conversion time: 4.156ms exactly.
  static TIMING-8300-US                         ::= 0x07       // Conversion time: 8.244ms exactly.


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

  // Die & Manufacturer Info Masks
  static DIE-ID-RID-MASK_                       ::= 0x000F //R  // Masks its part of the REGISTER-DIE-ID Register
  static DIE-ID-RID-OFFSET_                     ::= 0
  static DIE-ID-DID-MASK_                       ::= 0xFFF0 //R  // Masks its part of the REGISTER-DIE-ID Register
  static DIE-ID-DID-OFFSET_                     ::= 4      

  /**
  Masks for use with $REGISTER-CONFIGURATION_ register.
  */
  static CONF-RESET-MASK_                       ::= 0x8000
  static CONF-RESET-OFFSET_                     ::= 15
  static CONF-AVERAGE-MASK_                     ::= 0x0E00
  static CONF-AVERAGE-OFFSET_                   ::= 9
  static CONF-SHUNTVC-MASK_                     ::= 0x0038
  static CONF-SHUNTVC-OFFSET_                   ::= 3
  static CONF-BUSVC-MASK_                       ::= 0x01C0
  static CONF-BUSVC-OFFSET_                     ::= 6
  static CONF-MODE-MASK_                        ::= 0x0007
  static CONF-MODE-OFFSET_                      ::= 0
  static CONF-CH1-ENABLE-MASK_                  ::= 0b01000000_00000000
  static CONF-CH1-ENABLE-OFFSET_                ::= 14
  static CONF-CH2-ENABLE-MASK_                  ::= 0b00100000_00000000
  static CONF-CH2-ENABLE-OFFSET_                ::= 13
  static CONF-CH3-ENABLE-MASK_                  ::= 0b00010000_00000000
  static CONF-CH3-ENABLE-OFFSET_                ::= 12

  /**
  Masks for use with $REGISTER-MASK-ENABLE_ register.
  */
  static ALERT-CONVERSION-READY-FLAG_           ::= 0b00000000_00000001
  static ALERT-CONVERSION-READY-OFFSET_         ::= 0
  static ALERT-TIMING-CONTROL-FLAG_             ::= 0b00000000_00000010
  static ALERT-TIMING-CONTROL-OFFSET_           ::= 1
  static ALERT-POWER-VALID-FLAG_                ::= 0b00000000_00000100
  static ALERT-POWER-VALID-OFFSET_              ::= 2
  static ALERT-WARN-CH3-FLAG_                   ::= 0b00000000_00001000
  static ALERT-WARN-CH3-OFFSET_                 ::= 3
  static ALERT-WARN-CH2-FLAG_                   ::= 0b00000000_00010000
  static ALERT-WARN-CH2-OFFSET_                 ::= 4
  static ALERT-WARN-CH1-FLAG_                   ::= 0b00000000_00100000
  static ALERT-WARN-CH1-OFFSET_                 ::= 5
  static ALERT-SUMMATION-FLAG_                  ::= 0b00000000_01000000
  static ALERT-SUMMATION-OFFSET_                ::= 6
  static ALERT-CRITICAL-CH3-FLAG_               ::= 0b00000000_10000000
  static ALERT-CRITICAL-CH3-OFFSET_             ::= 7
  static ALERT-CRITICAL-CH2-FLAG_               ::= 0b00000001_00000000
  static ALERT-CRITICAL-CH2-OFFSET_             ::= 8
  static ALERT-CRITICAL-CH1-FLAG_               ::= 0b00000010_00000000
  static ALERT-CRITICAL-CH1-OFFSET_             ::= 9
  static CRITICAL-ALERT-LATCH-FLAG_             ::= 0b00000100_00000000
  static CRITICAL-ALERT-LATCH-OFFSET_           ::= 10
  static WARNING-ALERT-LATCH-FLAG_              ::= 0b00001000_00000000
  static WARNING-ALERT-LATCH-OFFSET_            ::= 11
  static SUMMATION-CONTROL-CH3-FLAG_            ::= 0b00010000_00000000
  static SUMMATION-CONTROL-CH3-OFFSET_          ::= 12
  static SUMMATION-CONTROL-CH2-FLAG_            ::= 0b00100000_00000000
  static SUMMATION-CONTROL-CH2-OFFSET_          ::= 13
  static SUMMATION-CONTROL-CH1-FLAG_            ::= 0b01000000_00000000
  static SUMMATION-CONTROL-CH1-OFFSET_          ::= 14 

  static INA3221-DEVICE-ID                      ::= 0x0322

  reg_/registers.Registers                      := ?  
  logger_/log.Logger                            := ?
  last-measure-mode_/int                        := MODE-SHUNT-BUS-CONTINUOUS
  shunt-resistor_/Map                           := {:}    
  current-LSB_/Map                              := {:}
  full-scale-current_/Map                       := {:}

  constructor dev/serial.Device --logger/log.Logger=(log.default.with-name "ina3221"):
    logger_ = logger
    reg_ = dev.registers
    
    if (read-device-identification != INA3221-DEVICE-ID): 
      logger_.debug "Device is NOT an INA3221 (Expecting ID:0x$(%04x INA3221-DEVICE-ID) Got ID:0x$(%04x read-device-identification))"
      logger_.debug "Device is man-id=0x$(%04x read-manufacturer-id) dev-id=0x$(%04x read-device-identification) rev=0x$(%04x read-device-revision)"
      throw "Device is not an INA3221."

    initialize-device_

  initialize-device_ -> none:
    // Maybe not required but the manual suggests you should do it.
    reset_
    
    // Initialize Default sampling, conversion timing, and measuring mode.
    set-sampling-rate AVERAGE-128-SAMPLES
    set-bus-conversion-time TIMING-1100-US       // Chip Default.  Shown here for clarity.
    set-shunt-conversion-time TIMING-1100-US     // Chip Default.  Shown here for clarity.
    set-measure-mode MODE-SHUNT-BUS-CONTINUOUS

    // Set Defaults for Shunt Resistor - module usually ships with R100 (0.100 Ohm) on all three
    // channels
    set-shunt-resistor 0.100 --channel=1
    set-shunt-resistor 0.100 --channel=2
    set-shunt-resistor 0.100 --channel=3
   
    /*
    Performing a single measurement during initialisation assists with accuracy for first reads.
    */
    trigger-measurement --wait=true

  /**
  $reset_: Reset Device.
  
  Setting bit 16 resets the device.  Once directly set, the bit self-clears afterwards.
  */
  reset_ -> none:
    write-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-RESET-MASK_ --offset=CONF-RESET-OFFSET_ --value=0b1

  /**
  $set-shunt-resistor: Set resistor and current range.
  
  Set shunt resistor value, input is in Ohms. If no --max-current is computed from +/-163.84 mV full scale. 
  Current range in amps.
  */
  set-shunt-resistor resistor/float --channel/int -> none:
    assert: 1 <= channel <= 3
    shunt-resistor_[channel]     = resistor
    current-LSB_[channel]        = SHUNT-VOLTAGE-LSB_ / resistor
    full-scale-current_[channel] = SHUNT-FULL-SCALE-VOLTAGE-LIMIT_ / resistor  // max current
    
  /** 
  $set-measure-mode: Sets Measure Mode. 
  
  One of 7 power modes: MODE-POWER-DOWN,TRIGGERED (bus or shunt, or both) or CONTINUOUS (either bus, 
  shunt, or both).  Keeps track of last measure mode set, in a local variable, to ensures device
  comes back on into the same previous mode when using 'power-on' and power-off functions.

  Mode         | Typical Supply Current | Description
  -------------|------------------------|------------------------------------------------------
  Power-Down   | 0.5 uA (typ)           | Conversions stopped; inputs biased off. Full recovery
               | 2.0 uA (max)           | to active takes ~40 µs after exiting power-down.
  -------------|------------------------|------------------------------------------------------
  Triggered    | appx 350 uA while      | Device wakes up, performs one measurement on all
               | converting             | enabled channels, then returns to power-down.
               |                        | Average current depends on duty.
  -------------|------------------------|------------------------------------------------------
  Continuous   | appx 350 uA (typ)	    | Device continuously measures shunt and/or bus voltages.
               | 450 uA (max)           |

  See section 6.5 of the Datasheet 'Electrical Characteristics'.
  */
  set-measure-mode mode/int -> none:
    write-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-MODE-MASK_ --offset=CONF-MODE-OFFSET_ --value=mode
    last-measure-mode_ = mode

  get-measure-mode -> int:
    return read-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-MODE-MASK_ --offset=CONF-MODE-OFFSET_

  /**
  $set-power-off: simple alias for disabling device.
  */
  set-power-off -> none:
    set-measure-mode MODE-POWER-DOWN

  /**
  $set-power-on: simple alias for enabling the device.

  Resets to the last mode set by $set-measure-mode.
  */
  set-power-on -> none:
    set-measure-mode last-measure-mode_
    sleep --ms=(get-estimated-conversion-time-ms)

  /**
  $set-bus-conversion-time: Sets conversion-time for bus only. See 'Conversion Time'.
  */
  set-bus-conversion-time code/int -> none:
    write-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-BUSVC-MASK_ --offset=CONF-BUSVC-OFFSET_ --value=code
  get-bus-conversion-time -> int:
    return read-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-BUSVC-MASK_ --offset=CONF-BUSVC-OFFSET_

  /**
  $set-shunt-conversion-time: Sets conversion-time for shunt only. See 'Conversion Time'.
  */
  set-shunt-conversion-time code/int -> none:
    write-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-SHUNTVC-MASK_ --offset=CONF-SHUNTVC-OFFSET_ --value=code
  get-shunt-conversion-time -> int:
    return read-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-SHUNTVC-MASK_ --offset=CONF-SHUNTVC-OFFSET_

  /** 
  $set-sampling-rate rate: Adjust Sampling Rate for measurements.  
  
  The sampling rate determines how often the device samples and averages the input 
  signals (bus voltage and shunt voltage) before storing them in the result registers.
  More samples lead to more stable values, but can lengthen the time required for a
  single measurement.  This is the register code/enum value, not actual rate. Can be
  converted back using  get-sampling-rate --count={enum}
  */
  set-sampling-rate code/int -> none:
    write-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-AVERAGE-MASK_ --offset=CONF-AVERAGE-OFFSET_ --value=code

  /**
  $get-sampling-rate --code: Retrieve current sampling rate selector/enum.
  
  The sampling rate determines how often the device samples and averages the input 
  signals (bus voltage and shunt voltage) before storing them in the result registers.
  More samples lead to more stable values, but can lengthen the time required for a
  single measurement.
  */
  get-sampling-rate -> int:
    return read-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-AVERAGE-MASK_ --offset=CONF-AVERAGE-OFFSET_

  /** $get-sampling-rate-us: Return human readable sampling count number. */
  get-sampling-rate-us -> int:
    return get-sampling-rate-from-enum get-sampling-rate


  /**
  Set the Critical-Alert threshold  --current (in amps) for a specific channel.

  Critical compares and will assert on each conversion.
  */
  set-critical-alert-threshold --current/float --channel/int -> none:
    assert: 1 <= channel <= 3
    threshold-value/int := (current / current-LSB_[channel]).round << 3
    write-register_ --register=(REGISTER-CRITICAL-ALERT-LIMIT-CH1_ + ((channel - 1) * 2)) --value=threshold-value
    //logger_.info "set-critical-alert-threshold: current=$(%0.3f current) [volts: $(%0.3f get-critical-alert-threshold --voltage --channel=channel)]"

  get-critical-alert-threshold --current --channel/int -> float:
    assert: 1 <= channel <= 3
    raw-read := reg_.read-u16-be (REGISTER-CRITICAL-ALERT-LIMIT-CH1_ + ((channel - 1) * 2))
    return ((raw-read & 0xFFF8) >> 3) * current-LSB_[channel]

  set-critical-alert-threshold --voltage/float --channel/int -> none:
    assert: 1 <= channel <= 3
    threshold-value/int := (voltage / SHUNT-VOLTAGE-LSB_).round << 3
    write-register_ --register=(REGISTER-CRITICAL-ALERT-LIMIT-CH1_ + ((channel - 1) * 2)) --value=threshold-value
    //logger_.info "set-critical-alert-threshold: voltage=$(%0.3f voltage) [current: $(%0.3f get-critical-alert-threshold --current --channel=channel)]"

  get-critical-alert-threshold --voltage --channel/int -> float:
    assert: 1 <= channel <= 3
    raw-read := reg_.read-u16-be (REGISTER-CRITICAL-ALERT-LIMIT-CH1_ + ((channel - 1) * 2))
    return ((raw-read & 0xFFF8) >> 3) * SHUNT-VOLTAGE-LSB_

  /**
  Set the Warning-Alert threshold  (in voltage or amps) for a specific channel.

  Both the per-channel 'Critical/Warning limits' and the 'Summation' limit 
  are programmed in the register in 'shunt voltage units' not actually in amps.
  Warning compares the averaged shunt voltage (per AVG bits) and will assert accordingly.
  */
  set-warning-alert-threshold --current/float --channel/int -> none:
    assert: 1 <= channel <= 3
    threshold-value/int := (current / current-LSB_[channel]).round
    if threshold-value > 4095: threshold-value = 4095
    if threshold-value < 0: threshold-value = 0
    write-register_ --register=(REGISTER-WARNING-ALERT-LIMIT-CH1_ + ((channel - 1) * 2)) --value=(threshold-value << 3)
    //logger_.info "set-warning-alert-threshold: current=$(%0.3f current) [volts: $(%0.3f get-warning-alert-threshold --voltage --channel=channel)]"

  get-warning-alert-threshold --current --channel/int -> float:
    assert: 1 <= channel <= 3
    raw-read := reg_.read-u16-be (REGISTER-WARNING-ALERT-LIMIT-CH1_ + ((channel - 1) * 2))
    return ((raw-read & 0xFFF8) >> 3) * current-LSB_[channel]

  set-warning-alert-threshold --voltage/float --channel/int -> none:
    assert: 1 <= channel <= 3
    threshold-value/int := (voltage / SHUNT-VOLTAGE-LSB_).round
    if threshold-value > 4095: threshold-value = 4095
    if threshold-value < 0: threshold-value = 0
    write-register_ --register=(REGISTER-WARNING-ALERT-LIMIT-CH1_ + ((channel - 1) * 2)) --value=(threshold-value << 3)
    //logger_.info "set-warning-alert-threshold: volts=$(%0.3f voltage) [current: $(%0.3f get-warning-alert-threshold --current --channel=channel)]"

  get-warning-alert-threshold --voltage --channel/int -> float:
    assert: 1 <= channel <= 3
    raw-read := reg_.read-u16-be (REGISTER-WARNING-ALERT-LIMIT-CH1_ + ((channel - 1) * 2))
    return ((raw-read & 0xFFF8) >> 3) * SHUNT-VOLTAGE-LSB_


  /** Valid power registers

  These two registers contains upper and lower values used to determine if 'power-valid' conditions are met.
  PV is not a “between L and U” window check.  PV (Power-Valid) works with hysteresis:
  - PV goes valid (PV pin = high) only after all three bus voltages have first risen above the upper limit.
  - Once valid, it stays valid until any bus voltage falls below the lower limit, then PV goes low (invalid).
  - PV needs all three channels “present”.
  - TI specifies PV requires all three bus-voltage channels to reach the upper limit. If a channel, is not in 
  use, tie its IN− to a used rail and leave IN+ floating, or PV will never declare “valid.” 
  - Simply disabling a channel in the config doesn’t make PV ignore it for this purpose.
  */

  /** 
  $set-valid-power-upper-limit: Sets upper limit for the valid power range.

  Power-on reset value for upper limit is 2710h = 10.000V.  See 'Valid power registers'
  */
  set-valid-power-upper-limit value/float -> none:
    raw-value := (value / POWER-VALID-LSB_).round << 3
    reg_.write-i16-be REGISTER-POWERVALID-UPPER-LIMIT_ raw-value

  /** 
  $get-valid-power-upper-limit: Gets upper limit for the valid power range.

  Power-on reset value for upper limit is 0x2710 = 10.0V. See 'Valid power registers'
  */
  get-valid-power-upper-limit -> float:
    raw-value := (reg_.read-i16-be REGISTER-POWERVALID-UPPER-LIMIT_) >> 3
    return raw-value * POWER-VALID-LSB_

  /** 
  $set-valid-power-lower-limit: Sets lower limit for the valid power range.

  Power-on reset value for lower limit is 0x2328 = 9.0V. See 'Valid power registers'
  */
  set-valid-power-lower-limit value/float -> none:
    raw-value := (value / POWER-VALID-LSB_).round << 3
    reg_.write-i16-be REGISTER-POWERVALID-LOWER-LIMIT_ raw-value

  /** 
  $get-valid-power-lower-limit: Gets lower limit for the valid power range.

  Power-on reset value for lower limit is 0x2328 = 9.0V. See 'Valid power registers'
  */
  get-valid-power-lower-limit -> float:
    raw-value := (reg_.read-i16-be REGISTER-POWERVALID-LOWER-LIMIT_) >> 3
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
    //logger_.info "set-shunt-summation-limit: current=$(current) [volts: $(get-shunt-summation-limit --voltage)]"

  get-shunt-summation-limit --current -> float:
    if not (current-LSB_.every: current-LSB_[it] == current-LSB_[1]):
      throw "set-summation-limit: summation invalid where shunt resistors differ."
    raw-counts := reg_.read-i16-be REGISTER-SHUNTVOLTAGE-SUM-LIMIT_
    return (raw-counts >> 1) * current-LSB_[1]

  /** 
  $trigger-measurement: perform a single conversion - without waiting.

  TRIGGERED MODE:  Executes single measurement
  CONTINUOUS MODE: Refreshes data
  */
  trigger-measurement --wait/bool=true -> none:
    mask-register-value/int   := reg_.read-u16-be REGISTER-MASK-ENABLE_               // Reading clears CNVR (Conversion Ready) Flag.
    config-register-value/int   := reg_.read-u16-be REGISTER-CONFIGURATION_    
    reg_.write-u16-be REGISTER-CONFIGURATION_ config-register-value                   // Starts conversion.
    if wait: wait-until-conversion-completed

  /**
  $wait-until-conversion-completed: execution blocked until conversion is completed.
  */
  wait-until-conversion-completed -> none:
    max-wait-time-ms/int   := get-estimated-conversion-time-ms
    current-wait-time-ms/int   := 0
    sleep-interval-ms/int := 50
    while busy:                                                      // Checks if sampling is completed.
      sleep --ms=sleep-interval-ms
      current-wait-time-ms += sleep-interval-ms
      if current-wait-time-ms >= max-wait-time-ms:
        logger_.debug "wait-until-conversion-completed: maxWaitTime $(max-wait-time-ms)ms exceeded - continuing"
        break

  /** 
  $busy: Returns true if conversion is still ongoing 
  
  Register MASK-ENABLE is read each poll.  In practices it does return the pre-clear CNVR
  bit, but reading also clears it. Loops using `while busy` will work (eg. false when 
  flag is 1), but it does mean a single poll will consume the flag. (This is already compensated
  for with the loop in 'wait-until-' functions'.)
  */
  busy -> bool:
    value/int := read-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-CONVERSION-READY-FLAG_ --offset=ALERT-CONVERSION-READY-OFFSET_
    return (value == 0)

  /** 
  $timing-control-alert
  
  Timing-control-alert flag indicator. Use this bit to determine if the timing control (TC)
  alert pin has been asserted through software rather than hardware. The bit setting
  corresponds to the status of the TC pin. This bit does not clear after it has been
  asserted unless the power is recycled or a software reset is issued. The default state
  for the timing control alert flag is high
  */
  timing-control-alert -> bool:
    value/int := read-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-TIMING-CONTROL-FLAG_ --offset=ALERT-TIMING-CONTROL-OFFSET_
    return (value == 1)

  /**
  $power-invalid-alert: Power-valid-alert flag indicator. 

  This bit can be used to be able to determine if the
  power valid (PV) alert pin has been asserted through software rather than hardware.
  The bit setting corresponds to the status of the PV pin. This bit does not clear until the
  condition that caused the alert is removed, and the PV pin has cleared.

  The PV pin = high means “power valid,” low means “invalid.” The PVF bit in Mask/Enable
  mirrors the PV status so firmware can read it. So printing “Valid-Power-Alert triggered”
  when PVF=1 is a bit confusing—PVF=1 really means “rails are valid”.
  */
  power-invalid-alert -> bool:
    value/int := read-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-POWER-VALID-FLAG_ --offset=ALERT-POWER-VALID-OFFSET_
    return (value == 0)

  /**
  $current-warning-alert: Warning-alert flag indicator.

  These bits are asserted if the corresponding channel
  averaged measurement has exceeded the warning alert limit, resulting in the Warning
  alert pin being asserted. Read these bits to determine which channel caused the
  warning alert. The Warning Alert Flag bits clear when the Mask/Enable register is read
  back
  */
  current-warning-alert --channel/int -> bool:
    assert: 1 <= channel <= 3
    if channel == 1:
      return ((read-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-WARN-CH1-FLAG_ --offset=ALERT-WARN-CH1-OFFSET_) == 1)
    if channel == 2:
      return ((read-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-WARN-CH2-FLAG_ --offset=ALERT-WARN-CH2-OFFSET_) == 1)
    if channel == 3:
      return ((read-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-WARN-CH3-FLAG_ --offset=ALERT-WARN-CH3-OFFSET_) == 1)
    return false

  /**
  $summation-alert: Summation-alert flag indicator.

  This bit is asserted if the Shunt Voltage Sum register
  exceeds the Shunt Voltage Sum Limit register. If the summation alert flag is asserted,
  the Critical alert pin is also asserted. The Summation Alert Flag bit is cleared when the
  Mask/Enable register is read back.
  */
  summation-alert -> bool:
    value/int := read-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-SUMMATION-FLAG_ --offset=ALERT-SUMMATION-OFFSET_
    return (value == 1)

  /**
  $critical-alert: Critical alert flag indicator.

  Critical-alert flag indicator. These bits are asserted if the corresponding channel
  measurement has exceeded the critical alert limit resulting in the Critical alert pin being
  asserted. Read these bits to determine which channel caused the critical alert. The
  critical alert flag bits are cleared when the Mask/Enable register is read back.
  */
  critical-alert --channel/int -> bool:
    assert: 1 <= channel <= 3
    if channel == 1:
      return ((read-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-CRITICAL-CH1-FLAG_ --offset=ALERT-CRITICAL-CH1-OFFSET_) == 1)
    if channel == 2:
      return ((read-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-CRITICAL-CH2-FLAG_ --offset=ALERT-CRITICAL-CH2-OFFSET_) == 1)
    if channel == 3:
      return ((read-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-CRITICAL-CH3-FLAG_ --offset=ALERT-CRITICAL-CH3-OFFSET_) == 1)
    return false

  /**
  $clear-alert: clears alerts.
  
  Test well when used: datasheet suggests simply reading the MASK-ENABLE register is enough to clear any alerts.
  */
  clear-alert -> none:
    register/int := read-register_ --register=REGISTER-MASK-ENABLE_

  /**
  $enable-channel: Enable channel.

  These bits allow each channel to be independently enabled or disabled.
  */
  enable-channel --channel/int -> none:
    assert: 1 <= channel <= 3
    if channel == 1: 
      write-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH1-ENABLE-MASK_ --offset=CONF-CH1-ENABLE-OFFSET_ --value=1
    else if channel == 2: 
      write-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH2-ENABLE-MASK_ --offset=CONF-CH2-ENABLE-OFFSET_ --value=1
    else if channel == 3: 
      write-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH3-ENABLE-MASK_ --offset=CONF-CH3-ENABLE-OFFSET_ --value=1

  /**
  $disable-channel: Disable channel
  */
  disable-channel --channel/int -> none:
    assert: 1 <= channel <= 3
    if channel == 1: 
      write-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH1-ENABLE-MASK_ --offset=CONF-CH1-ENABLE-OFFSET_ --value=0
    else if channel == 2: 
      write-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH2-ENABLE-MASK_ --offset=CONF-CH2-ENABLE-OFFSET_ --value=0
    else if channel == 3: 
      write-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH3-ENABLE-MASK_ --offset=CONF-CH3-ENABLE-OFFSET_ --value=0

  /**
  $enabled-channel-count: Count enabled channels
  */
  enabled-channel-count -> int:
    out := 0 
    out += read-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH1-ENABLE-MASK_ --offset=CONF-CH1-ENABLE-OFFSET_
    out += read-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH2-ENABLE-MASK_ --offset=CONF-CH2-ENABLE-OFFSET_
    out += read-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH3-ENABLE-MASK_ --offset=CONF-CH3-ENABLE-OFFSET_
    return out

  /**
  $channel-enabled: Boolean of if the channel is enabled
  */
  channel-enabled --channel/int -> bool:
    assert: 1 <= channel <= 3
    if channel == 1:
      return ((read-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH1-ENABLE-MASK_ --offset=CONF-CH1-ENABLE-OFFSET_) == 1)
    if channel == 2:
      return ((read-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH2-ENABLE-MASK_ --offset=CONF-CH2-ENABLE-OFFSET_) == 1)
    if channel == 3:
      return ((read-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH3-ENABLE-MASK_ --offset=CONF-CH3-ENABLE-OFFSET_) == 1)
    return false

  /**
  $enable-summation: Enable summation for channel
  */
  enable-summation --channel/int -> none:
    assert: 1 <= channel <= 3
    if channel == 1: 
      write-register_ --register=REGISTER-MASK-ENABLE_ --mask=SUMMATION-CONTROL-CH1-FLAG_ --offset=SUMMATION-CONTROL-CH1-OFFSET_ --value=1
    else if channel == 2: 
      write-register_ --register=REGISTER-MASK-ENABLE_ --mask=SUMMATION-CONTROL-CH2-FLAG_ --offset=SUMMATION-CONTROL-CH2-OFFSET_ --value=1
    else if channel == 3: 
      write-register_ --register=REGISTER-MASK-ENABLE_ --mask=SUMMATION-CONTROL-CH3-FLAG_ --offset=SUMMATION-CONTROL-CH3-OFFSET_ --value=1

  /**
  $disable-summation: Disable summation for channel
  */
  disable-summation --channel/int -> none:
    assert: 1 <= channel <= 3
    if channel == 1: 
      write-register_ --register=REGISTER-MASK-ENABLE_ --mask=SUMMATION-CONTROL-CH1-FLAG_ --offset=SUMMATION-CONTROL-CH1-OFFSET_ --value=0
    else if channel == 2: 
      write-register_ --register=REGISTER-MASK-ENABLE_ --mask=SUMMATION-CONTROL-CH2-FLAG_ --offset=SUMMATION-CONTROL-CH2-OFFSET_ --value=0
    else if channel == 3: 
      write-register_ --register=REGISTER-MASK-ENABLE_ --mask=SUMMATION-CONTROL-CH3-FLAG_ --offset=SUMMATION-CONTROL-CH3-OFFSET_ --value=0

  /**
  $channel-summation-enabled: Boolean of if channel is enabled in the summation
  */
  channel-summation-enabled --channel/int -> bool:
    assert: 1 <= channel <= 3
    if channel == 1:
      return ((read-register_ --register=REGISTER-MASK-ENABLE_ --mask=SUMMATION-CONTROL-CH1-FLAG_ --offset=SUMMATION-CONTROL-CH1-OFFSET_) == 1)
    if channel == 2:
      return ((read-register_ --register=REGISTER-MASK-ENABLE_ --mask=SUMMATION-CONTROL-CH2-FLAG_ --offset=SUMMATION-CONTROL-CH2-OFFSET_) == 1)
    if channel == 3:
      return ((read-register_ --register=REGISTER-MASK-ENABLE_ --mask=SUMMATION-CONTROL-CH3-FLAG_ --offset=SUMMATION-CONTROL-CH3-OFFSET_) == 1)
    return false

  /**
  $read-shunt-voltage: averaged shunt-voltage measurement for each channel 
  
  Stored as an 11 bit value in the 16 bit register - 1 bit lost for sign
  and the first three bits are simply unused and need to be shifted.
  */
  read-shunt-voltage --channel/int -> float?:
    if (channel < 1) or (channel > 3) : return null
    if not channel-enabled --channel=channel: return null
    raw-shunt-voltage := reg_.read-i16-be (REGISTER-SHUNT-VOLTAGE-CH1_ + ((channel - 1) * 2))
    return  (raw-shunt-voltage >> 3) * SHUNT-VOLTAGE-LSB_

  /**
  $read-bus-voltage: averaged shunt-voltage measurement for each channel 
  
  Stored the same way as $read-shunt-voltage.  while the full-scale range = 32.76V (decimal
  = 7FF8) LSB (BD0) = 8mV, the input range is only 26V, which must not be exceeded. 
  */
  read-bus-voltage --channel/int -> float?:
    if (channel < 1) or (channel > 3) : return null
    if not channel-enabled --channel=channel: return null
    raw-bus-voltage := reg_.read-u16-be (REGISTER-BUS-VOLTAGE-CH1_ + ((channel - 1) * 2))
    return  (raw-bus-voltage >> 3) * BUS-VOLTAGE-LSB_

  /**
  $read-shunt-current: averaged shunt current measurement for each channel 
  */
  read-shunt-current --channel/int -> float?:
    if (channel < 1) or (channel > 3) : return null
    if not channel-enabled --channel=channel: return null
    raw-shunt-counts := reg_.read-i16-be (REGISTER-SHUNT-VOLTAGE-CH1_ + ((channel - 1) * 2))
    return (raw-shunt-counts >> 3) * current-LSB_[channel]

  read-power --channel/int -> float?:
    if (channel < 1) or (channel > 3) : return null
    if not channel-enabled --channel=channel: return null
    bus-voltage := read-bus-voltage --channel=channel
    shunt-current := read-shunt-current --channel=channel
    if (bus-voltage == null) or (shunt-current == null): return null
    return bus-voltage * shunt-current

  /**
  read-supply-voltage:
  
  The INA3221 defines bus voltage as the voltage on the IN– pin to GND. The shunt voltage
  is IN+ – IN–. So the upstream supply at IN+ is: Vsupply@IN+ = Vbus(IN–→GND) + Vshunt(IN+−IN–).
  */
  read-supply-voltage --channel/int -> float?:
    if (channel < 1) or (channel > 3) : return null
    if not channel-enabled --channel=channel: return null
    return (read-bus-voltage --channel=channel) + (read-shunt-voltage --channel=channel)

  /** 
  $read-shunt-summation:

  The sum of the single conversion shunt voltages of the selected channels (enabled using summation 
  control function. This register is updated with the most recent sum following each complete cycle
  of all selected channels.
  */
  read-shunt-summation --voltage -> float:
    if not (current-LSB_.every: current-LSB_[it] == current-LSB_[1]):
      throw "read-shunt-summation: summation invalid where shunt resistors differ."
    raw-counts := reg_.read-i16-be REGISTER-SHUNTVOLTAGE-SUM_
    return (raw-counts >> 1) * SHUNT-VOLTAGE-LSB_

  read-shunt-summation --current -> float:
    if not (current-LSB_.every: current-LSB_[it] == current-LSB_[1]):
      throw "read-shunt-summation: summation invalid where shunt resistors differ."
    raw-counts := reg_.read-i16-be REGISTER-SHUNTVOLTAGE-SUM_
    return (raw-counts >> 1) * current-LSB_[1]

  /** 
  $get-estimated-conversion-time-ms: estimate a worst-case maximum waiting time based on the configuration.
  
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
  $get-conversion-time-us-from-enum: Returns microsecs for TIMING-x-US statics 0..7 (values as stored in the register).
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
  $get-sampling-rate-from-enum: Returns sample count for AVERAGE-x-SAMPLE statics 0..7 (values as stored in the register).
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
  $read-register_: Given that register reads are largely similar, implemented here.

  If the mask is left at 0xFFFF and offset at 0x0, it is a read from the whole register.
  */
  read-register_ --register/int --mask/int=0xFFFF --offset/int=0 -> any:
    register-value := reg_.read-u16-be register
    if mask == 0xFFFF and offset == 0:
      //logger_.debug "read-register_: reg-0x$(%02x register) is $(%04x register-value)"
      return register-value
    else:
      masked-value := (register-value & mask) >> offset
      //logger_.debug "read-register_: reg-0x$(%02x register) is $(bits-16 register-value) mask=[$(bits-16 mask) + offset=$(offset)] [$(bits-16 masked-value)]"
      return masked-value

  /** 
  $write-register_: Given that register writes are largely similar, implemented here.

  If the mask is left at 0xFFFF and offset at 0x0, it is a write to the whole register.
  */
  write-register_ --register/int --mask/int=0xFFFF --offset/int=0 --value/any --note/string="" -> none:
    max/int := mask >> offset                // allowed value range within field
    assert: ((value & ~max) == 0)            // value fits the field
    old-value/int := reg_.read-u16-be register

    // Split out the simple case
    if (mask == 0xFFFF) and (offset == 0):
      reg_.write-u16-be register (value & 0xFFFF)
      //logger_.debug "write-register_: Register 0x$(%02x register) set from $(%04x old-value) to $(%04x value) $(note)"
    else:
      new-value/int := old-value
      new-value     &= ~mask
      new-value     |= (value << offset)
      reg_.write-u16-be register new-value
      //logger_.debug "write-register_: Register 0x$(%02x register) set from $(bits-16 old-value) to $(bits-16 new-value) $(note)"

  /** 
  $read-manufacturer-id: Get Manufacturer identifier.
  
  Useful if expanding driver to suit an additional sibling devices.
  */
  read-manufacturer-id -> int:
    return reg_.read-u16-be REGISTER-MANUF-ID_
  
  /** 
  $read-device-identification: returns integer of device ID bits from register.
  
  Bits 4-15 Stores the device identification bits.
  */
  read-device-identification -> int:
    return read-register_ --register=REGISTER-DIE-ID_ --mask=DIE-ID-DID-MASK_ --offset=DIE-ID-DID-OFFSET_

  /** 
  $read-device-revision: Die Revision ID Bits.
  
  Bits 0-3 store the device revision number bits.
  */
  read-device-revision -> int:
    return read-register_ --register=REGISTER-DIE-ID_ --mask=DIE-ID-RID-MASK_ --offset=0


  /** 
  $mask-offset: calculate mask offset instead of passing them around?
  */
  mask-offset mask/int -> int:
    i := 0
    while (mask & (1 << i)) == 0: i += 1
    return i

  /** 
  bit-functions: Given here to help simplify code 
  */
  set-bit value/int mask/int -> int:    return value | mask
  clear-bit value/int mask/int -> int:  return value & ~mask
  toggle-bit value/int mask/int -> int: return value ^ mask

  /** 
  $bits-16: Displays bitmasks nicely when testing.
  */
  bits-16 x/int --min-display-bits/int=0 -> string:
    if (x > 255) or (min-display-bits > 8):
      out-string := "$(%b x)"
      out-string = out-string.pad --left 16 '0'
      out-string = "$(out-string[0..4]).$(out-string[4..8]).$(out-string[8..12]).$(out-string[12..16])"
      //logger_.debug "bits-16: 16 $(x) $(%0b x) gave $(out-string)"
      return out-string
    else if (x > 15) or (min-display-bits > 4):
      out-string := "$(%b x)"
      out-string = out-string.pad --left 8 '0'
      out-string = "$(out-string[0..4]).$(out-string[4..8])"
      //logger_.debug "bits-16: 08 $(x) $(%0b x) gave $(out-string)"
      return out-string
    else:
      out-string := "$(%b x)"
      out-string = out-string.pad --left 4 '0'
      out-string = "$(out-string[0..4])"
      //logger_.debug "bits-16: 04 $(x) $(%0b x) gave $(out-string)"
      return out-string
