
// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import ..src.ina3221 show *

/**
Triggered Updates Example:

A where a balance is required between Update Speed and Accuracy -
eg in a Battery-Powered Scenario.  The INA3221 is used to monitor a node’s power draw
to be able to estimate battery life.  The driver runs in continuous conversion mode by
default, sampling all the time at relatively short conversion times.  This has a higher
power requirement as the INA3221 is constantly awake and operating. In this case the 
driver needs to use triggered (single-shot) mode with longer conversion times and
averaging enabled.
*/

main:
  frequency := 400_000
  sda   := gpio.Pin 26
  scl   := gpio.Pin 25
  bus   := i2c.Bus --sda=sda --scl=scl --frequency=frequency
  event := 0

  ina3221-device := bus.device Ina3221.I2C_ADDRESS
  ina3221-driver := Ina3221 ina3221-device

  // Tests to occur on channel 1
  device-channel/int := 1

  // Prepare interim variables
  shunt-current-a/float  := 0.0
  bus-voltage-v/float    := 0.0
  load-power-mw/float    := 0.0

  // Set sample size to 1 to help show variation in voltage is noticable
  ina3221-driver.set-sampling-rate Ina3221.AVERAGE-1-SAMPLE
  ina3221-driver.set-bus-conversion-time Ina3221.TIMING-204-US
  ina3221-driver.set-shunt-conversion-time Ina3221.TIMING-204-US

  // Set shunt resistor for concerned channel
  ina3221-driver.set-shunt-resistor 0.100 --channel=device-channel
  
  // Read and display values every minute, but turn the device off in between
  10.repeat:
    // Three CONTINUOUS measurements, fluctuation expected
    ina3221-driver.set-measure-mode Ina3221.MODE-SHUNT-BUS-CONTINUOUS
    ina3221-driver.set-power-on
    print "CONTINUOUS measurements, fluctuation usually expected"
    5.repeat:
      shunt-current-a  = (ina3221-driver.read-shunt-current --channel=device-channel)                    // a
      bus-voltage-v    = (ina3221-driver.read-bus-voltage --channel=device-channel)                      // v
      load-power-mw    = (ina3221-driver.read-power --channel=device-channel) * 1000.0                   // mw
      print "      READ $(%02d it): $(%0.3f shunt-current-a)a  $(%0.4f bus-voltage-v)v  $(%0.1f load-power-mw)mw"
      sleep --ms=500
    
    // CHANGE MODE - trigger a measurement and switch off
    ina3221-driver.set-measure-mode Ina3221.MODE-SHUNT-BUS-CONTINUOUS

    3.repeat:
      ina3221-driver.set-power-on
      ina3221-driver.trigger-measurement
      ina3221-driver.set-power-off
      event = it
      print " TRIGGER EVENT #$(%02d event) - Registers read 5 times (new set of values but no change between reads)"

      5.repeat:
        shunt-current-a  = (ina3221-driver.read-shunt-current --channel=device-channel)                    // a
        bus-voltage-v    = (ina3221-driver.read-bus-voltage --channel=device-channel)                      // v
        load-power-mw    = (ina3221-driver.read-power --channel=device-channel) * 1000.0                   // mw
        print "  #$(%02d event) READ $(%02d it): $(%0.3f shunt-current-a)a  $(%0.4f bus-voltage-v)v  $(%0.1f load-power-mw)mw"
        sleep --ms=500

    print "Waiting 30 seconds"
    print ""
    sleep (Duration --s=30)
