
// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import ..src.ina3221 show *

/* Use Case: Changing the scale of currents measured

If the task is to measure smaller currents (in the milliamp range) the default 
shunt resistor could be replaced with a larger value resistor (e.g. 1.0 ΩOhm). This
increases the voltage drop per milliamp, giving the device finer resolution.  The 
consequence is that the maximum measurable current shrinks (since the device input
will saturate), as well as more power being dissipated in the shunt as heat.

Specifically: using the INA3221’s shunt measurement specs:
- Shunt voltage LSB = 40 uV
- Shunt voltage max = ±163.8 mV per channel

Shunt Resistor (SR) | Max Measurable Current | Shunt Resistor    | Resolution per bit | Note:
                    |                        | Wattage Reqt      |                    |
--------------------|------------------------|-------------------|--------------------|------------------------------------------ 
1.000 Ohm	        | 163.8 mA               | >0.125w           | 40 uA/bit          | Very fine resolution, only good for small
                    |                        |                   |                    | currents (<0.1 A).
--------------------|------------------------|-------------------|--------------------|------------------------------------------
0.100 Ohm (default) | 1.638 A                | >1.0 W            | 0.40 mA/bit        | Good sub 2A range.  Mind the thermal
                    |                        |                   |                    | rise.
--------------------|------------------------|-------------------|--------------------|------------------------------------------
0.050 Ohm           | 3.276 A                | >2.0 W            | 0.8 mA/bit         | Wider range; use Kelvin sense layout.
                    |                        |                   |                    | 
--------------------|------------------------|-------------------|--------------------|------------------------------------------
0.010 Ohm           | 16.38 A                | >3.0 W            | 4.0 mA/bit         | High range but coarser steps. heating and 
                    |                        | (5-10W preferred) |                    | PCB copper become critical.
--------------------|------------------------|-------------------|--------------------|------------------------------------------
*/

main:
  frequency      := 400_000
  sda            := gpio.Pin 26
  scl            := gpio.Pin 25
  bus            := i2c.Bus --sda=sda --scl=scl --frequency=frequency
  device-channel := 1

  ina3221-device := bus.device Ina3221.I2C_ADDRESS
  ina3221-driver := Ina3221 ina3221-device

  ina3221-driver.set-shunt-resistor 0.010 --channel=device-channel           // Reconfigure to the new 0.010 Ohm resistor on specific channel
  ina3221-driver.set-measure-mode Ina3221.MODE-SHUNT-BUS-CONTINUOUS          // Is the default, but setting again in case of consecutive tests without reset
  
  // Prepare variables
  shunt-current-ma/float := 0.0
  bus-voltage-v/float    := 0.0
  load-power-mw/float    := 0.0

  // example - disabling an unused channel
  ina3221-driver.disable-channel --channel=3

  // Continuously read and display values, in one row:
  print "OUTPUT FOR CHANNEL [$(device-channel)]"
  10.repeat:
    shunt-current-ma = (ina3221-driver.read-shunt-current --channel=device-channel) * 1000.0           // ma
    bus-voltage-v    = (ina3221-driver.read-bus-voltage --channel=device-channel)                      // v
    load-power-mw    = (ina3221-driver.read-power --channel=device-channel) * 1000.0                   // mw
    print "Channel [$(device-channel)]     $(%0.1f shunt-current-ma)ma  $(%0.3f bus-voltage-v)v  $(%0.1f (load-power-mw))mw"
    sleep --ms=500
