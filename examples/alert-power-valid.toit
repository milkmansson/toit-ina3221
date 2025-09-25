
// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import ..src.ina3221 show *


/** 

Tests: Power-Valid alert

**Toit prerequisites:**
These tests use 'print' function which in the simplest sense means
these tests should be run with `jag monitor` showing the output.  This 
code has not been optimised into functions etc, to ensure the process
behind the testing is clear.

**Wiring prerequisites:**
The Valid power test requires all three channels to be populated.
For these tests, the INA3221 is set on the 3.3v rail, and a small load 
is placed in series after the INA3221. This test is used with the modern
board version, see the Readme. The INA3221 GND pin is connected to the ESP32
GND alongside the rest of the 3v3 load.  The VPU can be tied to the 3.3v
rail for these tests.

Simply disabling a channel in the config doesn’t make PV ignore it
for this purpose.  Therefore To fake the other two channels for this
test, tie their IN- to the IN- on Channel 1, and leave the IN+ floating
for the two unused channels.

**Updates to PV:**
PV updates only after a bus-voltage conversion. After changing the PV
registers, the device compares the next bus conversions against the 
limits. If the PV flag is read immediately after being changed, it may
still show the old state. This example has a trigger/wait iteration
to ensure a complete a conversion.

**Understaning Power Valid alert:**
PV is hysteretic, not a “between L and U” window. PV goes VALID only
after all bus voltages rise above the UPPER limit, and returns INVALID
only after any bus voltage falls below the LOWER limit.
If we only want to flag “too high” (e.g., >3.6 V for a 3.3 V rail),
PV won’t do that.  PV only detects below-lower after having been valid.

**Test Process:**
1. set initial state and enable all 3 channels (PV checks all of them)
2. set fast conversions (so it reacts quickly)
3. show current state (in case test needs adjusting)
4. set PV limits so 3.3 V is inside the window - ensuring PV = valid
5. set PV limits so 3.3 V is below the lower limit and trigger PV = invalid
6. (flip back and forth to show the state changes)

**Result:**
1. If the board has a PV LED, it will blink on 1s, and off 1s, on repeat.

2. Display results will look like this:
```
[jaguar] INFO: program 0597e873-63ac-c6d4-ff90-5b117eb4e9b8 stopped
[jaguar] INFO: program f5d88697-210a-56bf-fd72-a7fe84e6290b started
      Current state 00: 0.040a  3.064v  147.8mw
      Current state 01: 0.036a  3.104v  112.3mw
      Current state 02: 0.036a  3.072v  135.2mw
      Current state 03: 0.032a  3.072v  123.5mw
      Current state 04: 0.028a  3.064v  111.2mw
CHANNEL[1] Invalid-Power-Alert actual=3.104 lower=2.800 upper=2.904  - PV should be VALID   → reads VALID       [SUCCESS]
CHANNEL[1] Invalid-Power-Alert actual=3.072 lower=3.200 upper=3.296  - PV should be INVALID → reads INVALID     [SUCCESS]

CHANNEL[1] Invalid-Power-Alert actual=3.096 lower=2.800 upper=2.904  - PV should be VALID   → reads VALID       [SUCCESS]
CHANNEL[1] Invalid-Power-Alert actual=3.072 lower=3.200 upper=3.296  - PV should be INVALID → reads INVALID     [SUCCESS]
```

**Troubleshooting:**
- The beginning of the test shows the current voltage on Channel 1.  If
  those values are out of bounds for the test, the constants in the code
  before main: may need adjusting. (eg $VALID-TEST-LOWER-LIMIT)
- PV goes VALID only after ALL bus voltages rise above the UPPER limit,
  and returns INVALID only after any bus voltage falls below the LOWER limit.
- If the LED doesn’t reflect PV: ensure the VPU pin (open-drain pull-up 
  domain) is connected to 3.3 V. No pull-up = no LED change.

*/

VALID-TEST-LOWER-LIMIT   := 2.8 //volts
VALID-TEST-UPPER-LIMIT   := 2.9 //volts

INVALID-TEST-LOWER-LIMIT := 3.2 //volts
INVALID-TEST-UPPER-LIMIT := 3.3 //volts

main:
  frequency              := 400_000
  sda                    := gpio.Pin 26
  scl                    := gpio.Pin 25
  bus                    := i2c.Bus --sda=sda --scl=scl --frequency=frequency
  device-channel         := 1
  shunt-current-a/float  := 0.0
  bus-voltage-v/float    := 0.0
  load-power-mw/float    := 0.0
  lower-limit            := 0.0
  upper-limit            := 0.0
  result                 := ""
  test-result            := ""
  result-info            := ""

  ina3221-device := bus.device Ina3221.I2C_ADDRESS
  ina3221-driver := Ina3221 ina3221-device

  // 1. set initial state and enable all 3 channels (PV checks all of them)
  ina3221-driver.set-shunt-resistor 0.100 --channel=device-channel           // Ensure set to default 0.100 shunt resistor
  ina3221-driver.set-measure-mode Ina3221.MODE-SHUNT-BUS-CONTINUOUS          // Is the default, but setting again in case of consecutive tests without reset
  ina3221-driver.set-power-on                                                // Setting these in case different tests are run consecutively
  ina3221-driver.enable-channel --channel=1
  ina3221-driver.enable-channel --channel=2
  ina3221-driver.enable-channel --channel=3

  // 2. set fast conversions (so INA3221 reacts quickly)
  ina3221-driver.set-sampling-rate Ina3221.AVERAGE-1-SAMPLE                  // Set sample size to 1 to help highlight variation and speed up conversion
  ina3221-driver.set-bus-conversion-time Ina3221.TIMING-140-US
  ina3221-driver.set-shunt-conversion-time Ina3221.TIMING-140-US

  // 3. show current state (in case test needs adjusting)
  5.repeat:
    shunt-current-a  = (ina3221-driver.read-shunt-current --channel=device-channel)                    // a
    bus-voltage-v    = (ina3221-driver.read-bus-voltage --channel=device-channel)                      // v
    load-power-mw    = (ina3221-driver.read-power --channel=device-channel) * 1000.0                   // mw
    print "      Current state $(%02d it): $(%0.3f shunt-current-a)a  $(%0.3f bus-voltage-v)v  $(%0.1f load-power-mw)mw"
    sleep --ms=500

  10.repeat:
    // 4. set PV limits so 3.3 V is inside the window → PV = valid
    ina3221-driver.set-valid-power-lower-limit VALID-TEST-LOWER-LIMIT
    ina3221-driver.set-valid-power-upper-limit VALID-TEST-UPPER-LIMIT
    ina3221-driver.trigger-measurement --wait=true
    lower-limit      = ina3221-driver.get-valid-power-lower-limit
    upper-limit      = ina3221-driver.get-valid-power-upper-limit
    bus-voltage-v    = (ina3221-driver.read-bus-voltage --channel=device-channel)
    result           = "$(ina3221-driver.power-invalid-alert ? "INVALID" : "VALID")"
    result-info      = "- PV should be VALID   → reads $(result)"
    test-result      = "$(result == "VALID" ? "SUCCESS" : "*** FAIL ***")"
    print "CHANNEL[$(device-channel)] Invalid-Power-Alert actual=$(%0.3f bus-voltage-v) lower=$(%0.3f lower-limit) upper=$(%0.3f upper-limit) $(result-info) \t[$(test-result)]"
    sleep --ms=1000

    // 5 set PV limits so 3.3 V is below the lower limit → PV = invalid
    ina3221-driver.set-valid-power-lower-limit INVALID-TEST-LOWER-LIMIT
    ina3221-driver.set-valid-power-upper-limit INVALID-TEST-UPPER-LIMIT
    ina3221-driver.trigger-measurement --wait=true
    lower-limit = ina3221-driver.get-valid-power-lower-limit
    upper-limit = ina3221-driver.get-valid-power-upper-limit
    bus-voltage-v    = (ina3221-driver.read-bus-voltage --channel=device-channel)
    result           = "$(ina3221-driver.power-invalid-alert ? "INVALID" : "VALID")"
    result-info      = "- PV should be INVALID → reads $(result)"
    test-result      = "$(result == "INVALID" ? "SUCCESS" : "*** FAIL ***")"
    print "CHANNEL[$(device-channel)] Invalid-Power-Alert actual=$(%0.3f bus-voltage-v) lower=$(%0.3f lower-limit) upper=$(%0.3f upper-limit) $(result-info) \t[$(test-result)]"
    sleep --ms=1000
    print ""
