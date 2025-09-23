
// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.   This also file includes derivative 
// work from other authors and sources.  See accompanying documentation.

// Datasheet: https://www.ti.com/lit/ds/symlink/ina3221.pdf

// https://done.land/components/power/measuringcurrent/viashunt/ina3221/


/**


The INA3221 works a bit differently from the INA226, so there is no register for calibration values, or 
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
  Masks for use with $REGISTER-MASK-ENABLE_ register.  Mostly alert constants.
  */
  static ALERT-CONVERSION-READY-FLAG_    ::= 0b00000000_00000001
  static ALERT-CONVERSION-READY-OFFSET_  ::= 0
  static ALERT-TIMING-CONTROL-FLAG_      ::= 0b00000000_00000010
  static ALERT-TIMING-CONTROL-OFFSET_    ::= 1
  static ALERT-POWER-VALID-FLAG_         ::= 0b00000000_00000100
  static ALERT-POWER-VALID-OFFSET_       ::= 2
  static ALERT-WARN-CH3-FLAG_            ::= 0b00000000_00001000
  static ALERT-WARN-CH3-OFFSET_          ::= 3
  static ALERT-WARN-CH2-FLAG_            ::= 0b00000000_00010000
  static ALERT-WARN-CH2-OFFSET_          ::= 4
  static ALERT-WARN-CH1-FLAG_            ::= 0b00000000_00100000
  static ALERT-WARN-CH1-OFFSET_          ::= 5
  static ALERT-SUMMATION-FLAG_           ::= 0b00000000_01000000
  static ALERT-SUMMATION-OFFSET_         ::= 6
  static ALERT-CRITICAL-CH3-FLAG_        ::= 0b00000000_10000000
  static ALERT-CRITICAL-CH3-OFFSET_      ::= 7
  static ALERT-CRITICAL-CH2-FLAG_        ::= 0b00000001_00000000
  static ALERT-CRITICAL-CH2-OFFSET_      ::= 8
  static ALERT-CRITICAL-CH1-FLAG_        ::= 0b00000010_00000000
  static ALERT-CRITICAL-CH1-OFFSET_      ::= 9
  static CRITICAL-ALERT-LATCH-FLAG_      ::= 0b00000100_00000000
  static CRITICAL-ALERT-LATCH-OFFSET_    ::= 10
  static WARNING-ALERT-LATCH-FLAG_       ::= 0b00001000_00000000
  static WARNING-ALERT-LATCH-OFFSET_     ::= 11
  static SUMMATION-CONTROL-CH3-FLAG_     ::= 0b00010000_00000000
  static SUMMATION-CONTROL-CH3-OFFSET_   ::= 12
  static SUMMATION-CONTROL-CH2-FLAG_     ::= 0b00100000_00000000
  static SUMMATION-CONTROL-CH2-OFFSET_   ::= 13
  static SUMMATION-CONTROL-CH1-FLAG_     ::= 0b01000000_00000000
  static SUMMATION-CONTROL-CH1-OFFSET_   ::= 14  
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

  // Configuration Register bitmasks.
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
      logger_.debug "Device is NOT an INA3221 (0x$(%04x INA3221-DEVICE-ID) [Device ID:0x$(%04x read-device-identification)]) "
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
    set-shunt-resistor --channel=1 --resistor=0.100
    set-shunt-resistor --channel=2 --resistor=0.100
    set-shunt-resistor --channel=3 --resistor=0.100
   
    print "power valid upper limit=$(get-valid-power-upper-limit)"
    print "power valid lower limit=$(get-valid-power-lower-limit)"
    //set-valid-power-lower-limit 3.3
    print "power valid lower limit=$(get-valid-power-lower-limit)"

    enable-channel --channel=1
    enable-channel --channel=2
    enable-channel --channel=3
    print "DISABLED CHANNEL 2"
    disable-channel --channel=2

    /*
    Performing a single measurement during initialisation assists with accuracy for first reads.
    */
    trigger-single-measurement
    wait-until-conversion-completed

  /**
  $reset_: Reset Device.
  
  Setting bit 16 resets the device.  Once directly set, the bit self-clears afterwards.
  */
  reset_ -> none:
    write-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-RESET-MASK_ --offset=CONF-RESET-OFFSET_ --value=0b1

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

  
  /** valid power registers

  These two registers contains upper and lower values used to determine if 'power-valid' conditions are met.
  The power-valid condition is reached when all BUS-VOLTAGE channels are between the LOWER and UPPER values set
  in the register. When the power-valid condition is met, the PV alert pin asserts high to indicate that the
  INA3221 has confirmed all bus voltage channels are in the correct range

  */

  /** 
  $set-valid-power-upper-limit: Sets upper limit for the valid power range.

  Power-on reset value for upper limit is 2710h = 10.000V.
  */
  set-valid-power-upper-limit value/float -> none:
    raw-value := (value / POWER-VALID-LSB_).to-int << 3
    reg_.write-i16-be REGISTER-POWERVALID-UPPER-LIMIT_ raw-value

  /** 
  $get-valid-power-upper-limit: Gets upper limit for the valid power range.

  Power-on reset value for upper limit is 2710h = 10.000V.
  */
  get-valid-power-upper-limit -> float:
    raw-value := (reg_.read-i16-be REGISTER-POWERVALID-UPPER-LIMIT_) >> 3
    return raw-value * POWER-VALID-LSB_

  /** 
  $set-valid-power-lower-limit: Sets lower limit for the valid power range.

  Power-on reset value for upper limit is 2328h = 9.000V.
  */
  set-valid-power-lower-limit value/float -> none:
    raw-value := (value / POWER-VALID-LSB_).to-int << 3
    reg_.write-i16-be REGISTER-POWERVALID-LOWER-LIMIT_ raw-value

  /** 
  $get-valid-power-lower-limit: Gets lower limit for the valid power range.

  Power-on reset value for upper limit is 2328h = 9.000V.
  */
  get-valid-power-lower-limit -> float:
    raw-value := (reg_.read-i16-be REGISTER-POWERVALID-LOWER-LIMIT_) >> 3
    return raw-value * POWER-VALID-LSB_

  /**
  $trigger-single-measurement: initiate a single measurement without waiting for completion.
  */
  trigger-single-measurement -> none:
    trigger-single-measurement --nowait
    wait-until-conversion-completed
  
  /** 
  $trigger-single-measurement: perform a single conversion - without waiting.
  */
  trigger-single-measurement --nowait -> none:
    mask-register-value/int   := reg_.read-u16-be REGISTER-MASK-ENABLE_               // Reading clears CNVR (Conversion Ready) Flag.
    config-register-value/int   := reg_.read-u16-be REGISTER-CONFIGURATION_    
    reg_.write-u16-be REGISTER-CONFIGURATION_ config-register-value                   // Starts conversion.

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
        logger_.debug "wait-until-conversion-completed: maxWaitTime $(max-wait-time-ms)ms exceeded - breaking"
        break

  /** 
  $busy: Returns true if conversion is still ongoing 
  
  Register MASK-ENABLE is read each poll.  In practices it does return the pre-clear CNVR
  bit, but reading also clears it. Loops using `while busy` will work (eg. false when 
  flag is 1), but it does mean a single poll will consume the flag. (This is already compensated
  for with the loop in 'wait-until-' functions'.)
  */
  busy -> bool:
    value/int := read-register_ --register=REGISTER-MASK-ENABLE_
    return (((read-register_ --register=REGISTER-MASK-ENABLE_) & ALERT-CONVERSION-READY-FLAG_) == 0)

  /**
  $enable-channel: Enable channel
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
  $disable-channel: Disable channel
  */
  enabled-channel-count -> int:
    out := 0 
    out += read-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH1-ENABLE-MASK_ --offset=CONF-CH1-ENABLE-OFFSET_
    out += read-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH2-ENABLE-MASK_ --offset=CONF-CH2-ENABLE-OFFSET_
    out += read-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH3-ENABLE-MASK_ --offset=CONF-CH3-ENABLE-OFFSET_
    return out

  /**
  $disable-channel: Disable channel
  */
  channel-enabled --channel/int -> bool:
    assert: 1 <= channel <= 3
    out/bool := false
    if channel == 1: 
      out = (read-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH1-ENABLE-MASK_ --offset=CONF-CH1-ENABLE-OFFSET_) == 1
      return out
    else if channel == 2: 
      out = (read-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH2-ENABLE-MASK_ --offset=CONF-CH2-ENABLE-OFFSET_) == 1
      return out
    else if channel == 3: 
      out = (read-register_ --register=REGISTER-CONFIGURATION_ --mask=CONF-CH3-ENABLE-MASK_ --offset=CONF-CH3-ENABLE-OFFSET_) == 1
      return out
    else:
      return out

  /**
  $set-shunt-resistor --resistor --max-current: Set resistor and current range.
  
  Set shunt resistor value, input is in Ohms. If no --max-current is computed from +/-163.84 mV full scale. 
  Current range in amps.
  */
  set-shunt-resistor --channel/int --resistor/float -> none:
    assert: 1 <= channel <= 3
    shunt-resistor_[channel]     = resistor
    current-LSB_[channel]        = SHUNT-VOLTAGE-LSB_ / resistor
    full-scale-current_[channel] = SHUNT-FULL-SCALE-VOLTAGE-LIMIT_ / resistor  // max current
    
    //count_to_A_[ch]  = SHUNT_LSB_V / resistor           // A per shunt-count
    //count_to_mA_[ch] = 1e3 * count_to_A_[ch]            // mA per shunt-count
    //imax_A_[ch]      = 0.16384 / resistor               // ≈ FS current (A)

  read-shunt-voltage --channel/int -> float?:
    if (channel < 1) or (channel > 3) : return null
    if not channel-enabled --channel=channel: return null
    raw-shunt-voltage := reg_.read-i16-be (REGISTER-SHUNT-VOLTAGE-CH1_ + ((channel - 1) * 2))
    return  (raw-shunt-voltage >> 3) * SHUNT-VOLTAGE-LSB_

  read-bus-voltage --channel/int -> float?:
    if (channel < 1) or (channel > 3) : return null
    if not channel-enabled --channel=channel: return null
    raw-bus-voltage := reg_.read-i16-be (REGISTER-BUS-VOLTAGE-CH1_ + ((channel - 1) * 2))
    return  (raw-bus-voltage >> 3) * BUS-VOLTAGE-LSB_

  read-current --channel/int -> float?:
    if (channel < 1) or (channel > 3) : return null
    if not channel-enabled --channel=channel: return null
    raw-shunt-counts := reg_.read-i16-be (REGISTER-SHUNT-VOLTAGE-CH1_ + ((channel - 1) * 2))
    return (raw-shunt-counts >> 3) * current-LSB_[channel]

  read-power --channel/int -> float?:
    if (channel < 1) or (channel > 3) : return null
    if not channel-enabled --channel=channel: return null
    return (read-bus-voltage --channel=channel) * (read-current --channel=channel)

  /**
  read-supply-voltage:
  
  The INA3221 defines bus voltage as the voltage on the IN– pin to GND. The shunt voltage is IN+ – IN–. So the upstream supply at IN+ is: Vsupply@IN+ = Vbus(IN–→GND) + Vshunt(IN+−IN–).
  */
  read-supply-voltage --channel/int -> float?:
    if (channel < 1) or (channel > 3) : return null
    if not channel-enabled --channel=channel: return null
    return (read-bus-voltage --channel=channel) * (read-shunt-voltage --channel=channel)

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
    total-us = ((total-us * 11.0) / 10.0).to-int

    // Return milliseconds, minimum 1 ms
    total-ms := ((total-us + 999) / 1000).to-int  // Ceiling.
    if total-ms < 1: total-ms = 1

    //logger_.debug "get-estimated-conversion-time-ms is: $(total-ms)ms"
    return total-ms

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
