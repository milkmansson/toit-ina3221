
// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import ..src.ina3221 show *


/** 

Tests: Current Alert Thresholds

**Toit prerequisites:**
These tests use 'print' function which in the simplest sense means
these tests should be run with `jag monitor` showing the output.  This 
code has not been optimised into functions etc, to ensure the process
behind the testing is clear.

**Wiring prerequisites**
Simply establish a load on the INA3221 for testing.

**Warning and Critical definitions**
Both the per-channel Critical/Warning limits (this example) and the 
'Summation' limit are programmed in the register in 'shunt voltage units'
not actually in amps.
Critical compares each conversion; Warning compares the averaged
shunt reading.  The default shunt resistor for most INA3221 boards
is R100 (0.100 Ohm) meaning current must be set in increments 
of minimum 0.0004 A (0.4 ma).

**Test Process:**
1. set initial state and enable channel 1
2. set fast conversions (so it reacts quickly)
3. show current state (in case the test needs adjusting)
4. set warning limits so current is above the limit - triggering warning alert
5. set critical limits so current is above the limit - triggering critical alert
6. (flip back and forth to show the state changes)

**Results:**
If the appropriate values are set for TEST-WARNING-THRESHOLD and for
TEST-CRITICAL-THRESHOLD:
1. If the module has C and W LEDs, these should light and go out in
   1s sequence according to the code example: off-off 1s, on-off 1s, 
   on-on 1s, then repeat.  
2. The monitor should show the following output:
```
[jaguar] INFO: program 3d38d64e-5801-fad6-976d-8a4cc8cc1e6f started
      Current state 00: 0.006a  3.184v  17.9mw
      Current state 01: 0.005a  3.200v  19.2mw
      Current state 02: 0.004a  3.192v  16.6mw
      Current state 03: 0.005a  3.184v  15.3mw
      Current state 04: 0.004a  3.200v  16.6mw
Current Alert actual=0.0056 w-limit=1.6380 c-limit=1.6380 - alert should be NORMAL → reads WARNING=NORMAL CRITICAL=NORMAL       [SUCCESS]
Current Alert actual=0.0064 w-limit=0.0032 c-limit=1.6380 - Warning should ALERT   → reads WARNING=ALERT CRITICAL=NORMAL        [SUCCESS]
Current Alert actual=0.0072 w-limit=0.0032 c-limit=0.0040 - Critical should ALERT  → reads WARNING=ALERT CRITICAL=ALERT         [SUCCESS]

Current Alert actual=0.0056 w-limit=1.6380 c-limit=1.6380 - alert should be NORMAL → reads WARNING=NORMAL CRITICAL=NORMAL       [SUCCESS]
Current Alert actual=0.0060 w-limit=0.0032 c-limit=1.6380 - Warning should ALERT   → reads WARNING=ALERT CRITICAL=NORMAL        [SUCCESS]
Current Alert actual=0.0076 w-limit=0.0032 c-limit=0.0040 - Critical should ALERT  → reads WARNING=ALERT CRITICAL=ALERT         [SUCCESS]
```

**Troubleshooting:**
- The lowest sensitivity on the INA3221 for current 0.0004 A, assuming
  the default shunt resistor is 0.100 Ω (R100).

*/

TEST-WARNING-THRESHOLD    := 0.0030 //amps
TEST-CRITICAL-THRESHOLD   := 0.0040 //amps

main:
  frequency      := 400_000
  sda            := gpio.Pin 26
  scl            := gpio.Pin 25
  bus            := i2c.Bus --sda=sda --scl=scl --frequency=frequency
  device-channel := 1

  ina3221-device := bus.device Ina3221.I2C_ADDRESS
  ina3221-driver := Ina3221 ina3221-device

  // Prepare variables
  bus-voltage-v/float           := 0.0
  load-power-mw/float           := 0.0
  current-current/float         := 0.0
  warning-result/string         := ""
  critical-result/string        := ""
  result-info/string            := ""
  test-result/string            := ""
  warning-threshold-read/float  := 0.0
  critical-threshold-read/float := 0.0
  
  default-warning-threshold     := ina3221-driver.get-warning-alert-threshold --current --channel=device-channel
  default-critical-threshold    := ina3221-driver.get-critical-alert-threshold --current --channel=device-channel

  // 1. set initial state
  ina3221-driver.disable-channel --channel=1                                 // Disable all channels, and enable only channel used in this test
  ina3221-driver.disable-channel --channel=2
  ina3221-driver.disable-channel --channel=3
  ina3221-driver.enable-channel --channel=device-channel
  ina3221-driver.set-shunt-resistor 0.100 --channel=device-channel           // Ensure set to default 0.100 shunt resistor
  ina3221-driver.set-measure-mode Ina3221.MODE-SHUNT-BUS-CONTINUOUS          // Is the default, but setting again in case of consecutive tests without reset
  ina3221-driver.set-power-on                                                // Setting these in case different tests are run consecutively

  // 2. set fast conversions (so INA3221 reacts quickly)
  ina3221-driver.set-sampling-rate Ina3221.AVERAGE-1-SAMPLE                  // Set sample size to 1 to help highlight variation and speed up conversion
  ina3221-driver.set-bus-conversion-time Ina3221.TIMING-140-US
  ina3221-driver.set-shunt-conversion-time Ina3221.TIMING-140-US

  // 3. show current state (in case test needs adjusting)
  5.repeat:
    current-current  = (ina3221-driver.read-shunt-current --channel=device-channel)                    // a
    bus-voltage-v    = (ina3221-driver.read-bus-voltage --channel=device-channel)                      // v
    load-power-mw    = (ina3221-driver.read-power --channel=device-channel) * 1000.0                   // mw
    print "      Current state $(%02d it): $(%0.3f current-current)a  $(%0.3f bus-voltage-v)v  $(%0.1f load-power-mw)mw"
    sleep --ms=500

  10.repeat:
    // Default values 
    ina3221-driver.set-warning-alert-threshold --current=default-warning-threshold --channel=device-channel
    ina3221-driver.set-critical-alert-threshold --current=default-critical-threshold --channel=device-channel
    ina3221-driver.trigger-measurement --wait=true
    warning-threshold-read  = ina3221-driver.get-warning-alert-threshold --current --channel=device-channel
    critical-threshold-read = ina3221-driver.get-critical-alert-threshold --current --channel=device-channel
    current-current         = ina3221-driver.read-shunt-current --channel=device-channel
    warning-result          = "$(current-current < warning-threshold-read  ? "NORMAL" : "ALERT")"
    critical-result         = "$(current-current < critical-threshold-read ? "NORMAL" : "ALERT")"
    result-info             = "- alert should be NORMAL → reads WARNING=$(warning-result) CRITICAL=$(critical-result)"
    test-result             = "$((warning-result == "NORMAL") and (critical-result == "NORMAL") ? "SUCCESS" : "*** FAIL ***")"
    print "Current Alert actual=$(%0.4f current-current) w-limit=$(%0.4f warning-threshold-read) c-limit=$(%0.4f critical-threshold-read) $(result-info) \t[$(test-result)]"
    sleep --ms=1000
    // 4. set WARNING limits so current is above the limit - triggering warning alert
    ina3221-driver.set-warning-alert-threshold --current=TEST-WARNING-THRESHOLD --channel=device-channel
    ina3221-driver.set-critical-alert-threshold --current=default-critical-threshold --channel=device-channel
    ina3221-driver.trigger-measurement --wait=true
    warning-threshold-read  = ina3221-driver.get-warning-alert-threshold --current --channel=device-channel
    critical-threshold-read = ina3221-driver.get-critical-alert-threshold --current --channel=device-channel
    current-current         = ina3221-driver.read-shunt-current --channel=device-channel
    warning-result          = "$(current-current < warning-threshold-read  ? "NORMAL" : "ALERT")"
    critical-result         = "$(current-current < critical-threshold-read ? "NORMAL" : "ALERT")"
    result-info             = "- Warning should ALERT   → reads WARNING=$(warning-result) CRITICAL=$(critical-result)"
    test-result             = "$((warning-result == "ALERT") and (critical-result == "NORMAL") ? "SUCCESS" : "*** FAIL ***")"
    print "Current Alert actual=$(%0.4f current-current) w-limit=$(%0.4f warning-threshold-read) c-limit=$(%0.4f critical-threshold-read) $(result-info) \t[$(test-result)]"
    sleep --ms=1000

    // 4. set CRITICAL limits so current is above the limit - triggering warning alert
    ina3221-driver.set-warning-alert-threshold --current=TEST-WARNING-THRESHOLD --channel=device-channel
    ina3221-driver.set-critical-alert-threshold --current=TEST-CRITICAL-THRESHOLD --channel=device-channel
    ina3221-driver.trigger-measurement --wait=true
    warning-threshold-read  = ina3221-driver.get-warning-alert-threshold --current --channel=device-channel
    critical-threshold-read = ina3221-driver.get-critical-alert-threshold --current --channel=device-channel
    current-current         = ina3221-driver.read-shunt-current --channel=device-channel
    warning-result          = "$(current-current < warning-threshold-read  ? "NORMAL" : "ALERT")"
    critical-result         = "$(current-current < critical-threshold-read ? "NORMAL" : "ALERT")"
    result-info             = "- Critical should ALERT  → reads WARNING=$(warning-result) CRITICAL=$(critical-result)"
    test-result             = "$((warning-result == "ALERT") and (critical-result == "ALERT") ? "SUCCESS" : "*** FAIL ***")"
    print "Current Alert actual=$(%0.4f current-current) w-limit=$(%0.4f warning-threshold-read) c-limit=$(%0.4f critical-threshold-read) $(result-info) \t[$(test-result)]"
    sleep --ms=1000

    print ""
