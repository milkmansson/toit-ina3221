
// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import ..src.ina3221 show *

/** 
Simple Continuous Measurements Example

Simplest use case assumes an unmodified module with default wiring guidelines followed.  
(Please see the Readme for pointers & guidance.) This example assumes:
 - Module shunt resistor value R100 (0.1 Ohm)
 - Sample size of 1 (eg, no averaging)
 - Conversion time of 1100us
 - Continuous Mode
 - Default wiring and default module shunt (see docs.)
*/

main:
  frequency := 400_000
  sda := gpio.Pin 26
  scl := gpio.Pin 25
  bus := i2c.Bus --sda=sda --scl=scl --frequency=frequency

  ina3221-device := bus.device Ina3221.I2C_ADDRESS
  ina3221-driver := Ina3221 ina3221-device


  ina3221-driver.set-measure-mode Ina3221.MODE-SHUNT-BUS-CONTINUOUS       // Is the default, but setting again in case of consecutive tests without reset
  ina3221-driver.set-sampling-rate Ina3221.AVERAGE-1-SAMPLE
  ina3221-driver.trigger-measurement                                      // Wait for first registers to be ready (eg enough samples)
  
  // Tests to occur on channel 1
  device-channel/int := 1

  // Prepare variables
  shunt-current-a/float  := 0.0
  bus-voltage-v/float    := 0.0
  load-power-mw/float    := 0.0

  // Continuously read and display values
  10.repeat:
    10.repeat:
      shunt-current-a  = (ina3221-driver.read-shunt-current --channel=device-channel)                    // a
      bus-voltage-v    = (ina3221-driver.read-bus-voltage --channel=device-channel)                      // v
      load-power-mw    = (ina3221-driver.read-power --channel=device-channel) * 1000.0                   // mw
      
      print "CHANNEL[$(device-channel)]:   Measurement $(%02d it): $(%0.3f shunt-current-a)ma  $(%0.3f (bus-voltage-v))v  $(%0.2f (load-power-mw))mw"
      sleep --ms=500

    print "Waiting 30 seconds"
    print ""
    sleep (Duration --s=30)
