
// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import ..src.ina3221 show *


/** 

Tests: Summation

**Toit prerequisites:**
These tests use 'print' function which in the simplest sense means
these tests should be run with `jag monitor` showing the output.

**Summation - in practise:**
The summing spoken of here is not summing the bus voltages - eg, 3.3v or 5v.
Summing shunt voltages is essentially the summing of currents (when shunts
are equal). That gives a hardware total-current budget.  Whilst the library 
provides functions for voltage and current, current appears most practical 
and is shown in this example.
Note that for the INA3221, the default 6.553 A is a 'limit' - the register’s 
absolute max, not a reachable sum. Aim for less than 4.914 A total (for three 
channels with shunt resistors at 0.1 Ohm)
Practical examples of Summation in use:
- Enforce USB/port current budgets. In a USB-powered device with several sub-rails,
  trip when the combined draw approaches 500 mA/900 mA.
- Thermal / trace protection. Keep the board copper or connector within safe current.
- Brownout prevention. Pair with the Power-Valid window: if total current
  spikes (sum trips) and bus drops, shut down non-critical loads.

**Wiring prerequisites**
Use loads on all three channels.  

**Summation test**
Summation on the INA3221 adds the single shunt-voltage conversions
of whichever channels are selected, compares that sum against the Shunt-Voltage
Sum-Limit register, and if the sum exceeds the limit it asserts the Critical 
alert (and sets the Summation Alert (SF) flag).  Individually, each channel
is below the per-channel critical limit.

**Test Process:**
1. set initial state and enable channels
2. set reasonable average to ensure stable measurements 
3. enable summation on all three channels, clear any alerts
4. show current state (in case the test needs adjusting
5. set per-channel critical limits high so the SUM alert trips first
6. get the current amp draw and set it as a target
6. iterate through a range of tests from 0 through 2x the measurement
7. test values through the range to show when the alert occurs.

**Results:**
If the appropriate values are set for TEST-WARNING-THRESHOLD and for
TEST-CRITICAL-THRESHOLD:
1. If the module has C and W LEDs, these should light and go out in
   1s sequence according to the code example: off-off 1s, on-off 1s, 
   on-on 1s, then repeat.  
2. The monitor should show the following output:
```
```

**Troubleshooting**
- If the shunts aren’t equal, the hardware sum no longer tracks total current.
  In that case either use equal shunts for the summed group, or, don’t rely
  on hardware summation.  Compute a software total current instead, and set
  alerts per channel.


*/

SHUNT-CURRENT-MAX  := 1.638 //amps   // theroetical maximum, not practical

ina3221-device            := ?
ina3221-driver            := ?

main:
  frequency      := 400_000
  sda            := gpio.Pin 26
  scl            := gpio.Pin 25
  bus            := i2c.Bus --sda=sda --scl=scl --frequency=frequency

  ina3221-device = bus.device Ina3221.I2C_ADDRESS
  ina3221-driver = Ina3221 ina3221-device

  test-result/string          := ""
  current-current-test/float  := 0.0

  // 1. set initial state and enable channels
  ina3221-driver.enable-channel --channel=1                                  // Disable all channels, and enable only channel used in this test
  ina3221-driver.enable-channel --channel=2
  ina3221-driver.enable-channel --channel=3
  ina3221-driver.set-shunt-resistor 0.100 --channel=1                        // Ensure set to default 0.100 shunt resistor
  ina3221-driver.set-shunt-resistor 0.100 --channel=2
  ina3221-driver.set-shunt-resistor 0.100 --channel=3
  ina3221-driver.set-measure-mode Ina3221.MODE-SHUNT-BUS-TRIGGERED          // Is the default, but setting again in case of consecutive tests without reset
  ina3221-driver.set-power-on                                                // Setting these in case different tests are run consecutively

  // 2. set reasonable average to ensure stable measurements 
  ina3221-driver.set-sampling-rate Ina3221.AVERAGE-512-SAMPLES               // Set sample size to 512 to ensure some stability in setting and measuring
  ina3221-driver.set-bus-conversion-time Ina3221.TIMING-332-US
  ina3221-driver.set-shunt-conversion-time Ina3221.TIMING-332-US

  // 3. enable summation on all three channels, clear any alerts
  ina3221-driver.enable-summation --channel=1
  ina3221-driver.enable-summation --channel=2
  ina3221-driver.enable-summation --channel=3
  ina3221-driver.clear-alert

  // 4. show current state (in case the test needs adjusting
  3.repeat:
    ina3221-driver.trigger-measurement --wait=true
    print " Original State: $(show-current-state --channel=(it + 1))"         //repeat is zero based
  print ""

  // 5. set high limits to allow sum alert to trip first
  3.repeat:
    ina3221-driver.set-critical-alert-threshold --current=SHUNT-CURRENT-MAX --channel=(it + 1)  //repeat is zero based
    ina3221-driver.set-warning-alert-threshold --current=SHUNT-CURRENT-MAX --channel=(it + 1)  //repeat is zero based

  // 6. get the current amp draw and set it as a target
  test-target/float := 0.0
  3.repeat:
    ina3221-driver.trigger-measurement --wait=true
    test-target += ina3221-driver.read-shunt-current --channel=(it + 1) 

  10.repeat:
    current-current-test = (test-target / 5) * it
    ina3221-driver.set-shunt-summation-limit --current=current-current-test
    ina3221-driver.trigger-measurement --wait=true
    3.repeat:
      print "  Current State: $(show-current-state --channel=(it + 1))"         //repeat is zero based
    test-result = "$((ina3221-driver.summation-alert == true) ? "ALERT" : "NORMAL")"
    print "        Test #$(it): limit=$(%0.3f current-current-test) result = $(test-result)"  
    print ""

  // Put back to continuous when complete
  ina3221-driver.set-measure-mode Ina3221.MODE-SHUNT-BUS-TRIGGERED

show-current-state --channel/int -> string:
  shunt-current-a/float  := (ina3221-driver.read-shunt-current --channel=channel)                    // a
  shunt-voltage-mv/float  := (ina3221-driver.read-shunt-voltage --channel=channel) * 1000            // mv
  bus-voltage-v/float    := (ina3221-driver.read-bus-voltage --channel=channel)                      // v
  load-power-mw/float    := (ina3221-driver.read-power --channel=channel) * 1000.0                   // mw
  return "CH$(channel): Shunt: $(%0.3f shunt-current-a)a  $(%0.3f shunt-voltage-mv)mv   Bus: $(%0.3f bus-voltage-v)v  Power: $(%0.1f load-power-mw)mw"
