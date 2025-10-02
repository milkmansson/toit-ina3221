# Toit Library for the TI INA3221 Triple-Channel Voltage/Current Monitor IC
Toit driver for the INA3221: three channels of shunt + bus voltage monitoring with alerts. Unlike INA226, there is no calibration register— current is computed in software from Vshunt and shunt resistor values.

## About the Device
The INA3221 from Texas Instruments is a precision digital power monitor IC with an integrated 16-bit ADC.  It measures the voltage drop across a shunt resistor to calculate current, monitors the bus voltage directly, and internally multiplies the two to report power consumption.

- Channels: 3 (independent enable; common timing/mode).
- Shunt voltage: ±163.84 mV full-scale, 40 uV/LSB. Data are left-justified in bits 14..3; right-shift by 3 before scaling.
- Bus voltage: 0–26 V input (coding to 32.76 V), 8 mV/LSB
- Current & power: no current/power registers. Computed in this driver using: I = Vshunt / Rshunt, P = Vbus × I.
- Conversion times: 140 us … 8.244 ms + averaging (1…1024).
- Operating modes: continuous and single-shot (triggered) that measures all enabled channels once then returns to power-down; separate power-down mode with ~40 us recovery.
- Supply current: 350 uA typ (active), 0.5 uA typ (power-down).
- I²C / SMBus: four programmable addresses (A0 pin).
- Alerts: Critical/Warning (per-channel overcurrent via shunt), Power-Valid window (all bus voltages between upper/lower limits), Timing Control and Summation alerts.
- Max measurable current is 0.16384 V / Rshunt.

## Wiring
There are two main variations of module both with different wiring requirements (ADD PICTURES AND DESCRIBE)

## Measuring / operating modes
- Continuous: device cycles shunt→bus for each enabled channel in order. Registers update after averaging.
- Single-shot/Triggered: Once triggered, the chip converts every enabled channel once, then enters power-down.
- Power-down: lowest quiescent; registers keep last values; 40 us recovery time to activate.





## Measure Mode Power Draw





## Valid Power

  /** Valid power registers

  Power-on reset value for upper limit is 2710h = 10.000V.  See 'Valid power registers'

  These two registers contains upper and lower values used to determine if 'power-valid' conditions are met.
  PV is not a “between L and U” window check.  PV (Power-Valid) works with hysteresis:
  - PV goes valid (PV pin = high) only after all three bus voltages have first risen above the upper limit.
  - Once valid, it stays valid until any bus voltage falls below the lower limit, then PV goes low (invalid).
  - PV needs all three channels “present”.
  - TI specifies PV requires all three bus-voltage channels to reach the upper limit. If a channel, is not in
  use, tie its IN− to a used rail and leave IN+ floating, or PV will never declare “valid.”
  - Simply disabling a channel in the config doesn’t make PV ignore it for this purpose.
  */



## Critical and Warning Alerts
Difference between warning and critical alert thresholds...
The warning alert monitors the averaged value of each shunt-voltage channel. The averaged value of each
shunt-voltage channel is based on the number of averages set with the averaging mode bits (AVG1-3) in the
Configuration register. The average value updates in the shunt-voltage output register each time there is a
conversion on the corresponding channel. The device compares the averaged value to the value programmed in
the corresponding-channel Warning Alert Limit register to determine if the averaged value has been exceeded,
indicating whether the average current is too high. At power-up, the default warning-alert limit value for each
channel is set to the positive full-scale value, effectively disabling the alert. The corresponding limit registers can
be programmed at any time to begin monitoring for out-of-range conditions. The Warning alert pin pulls low if
any channel measurements exceed the limit present in the corresponding-channel Warning Alert Limit register.
When the Warning alert pin pulls low, read the Mask/Enable register to determine which channel warning alert
flag indicator bit (WF1-3) is asserted (= 1)

  Both the per-channel 'Critical/Warning limits' and the 'Summation' limit
  are programmed in the register in 'shunt voltage units' not actually in amps.
  Warning compares the averaged shunt voltage (per AVG bits) and will assert accordingly.



  The sampling rate determines how often the device samples and averages the input
  signals (bus voltage and shunt voltage) before storing them in the result registers.
  More samples lead to more stable values, but can lengthen the time required for a
  single measurement.  This is the register code/enum value, not actual rate. Can be
  converted back using  get-sampling-rate --count={enum}

  The sampling rate determines how often the device samples and averages the input
  signals (bus voltage and shunt voltage) before storing them in the result registers.
  More samples lead to more stable values, but can lengthen the time required for a
  single measurement.
  */

***
  Register MASK-ENABLE is read each poll.  In practices it does return the pre-clear CNVR
  bit, but reading also clears it. Loops using `while busy` will work (eg. false when
  flag is 1), but it does mean a single poll will consume the flag. (This is already compensated
  for with the loop in 'wait-until-' functions'.)

***
  One of 7 power modes: MODE-POWER-DOWN,TRIGGERED (bus or shunt, or both) or CONTINUOUS (either bus,
  shunt, or both).  Keeps track of last measure mode set, in a local variable, to ensures device
  comes back on into the same previous mode when using 'power-on' and power-off functions.

  Mode         | Typical Supply Current | Description
  -------------|------------------------|------------------------------------------------------
  Power-Down   | 0.5 uA (typ) 2.0 uA (max)  | Conversions stopped; inputs biased off. Full recovery to active takes ~40 µs after exiting power-down.
  Triggered  (all)  | appx 350 uA (while converting) | Device wakes up, performs one measurement on all enabled channels, then returns to power-down.  Average current depends on duty.
  Continuous  (all) | appx 350 uA (typ)	450 uA (max) | Device continuously measures shunt and/or bus voltages.

read-bus-voltage etc
  Stored the same way as $read-shunt-voltage.  while the full-scale range = 32.76V (decimal
  = 7FF8) LSB (BD0) = 8mV, the input range is only 26V, which must not be exceeded.


  The INA3221 defines bus voltage as the voltage on the IN– pin to GND. The shunt voltage
  is IN+ – IN–. So the upstream supply at IN+ is: Vsupply@IN+ = Vbus(IN–→GND) + Vshunt(IN+−IN–).

Shunt Summation
  $read-shunt-summation:

  The sum of the single conversion shunt voltages of the selected channels (enabled using summation
  control function. This register is updated with the most recent sum following each complete cycle
  of all selected channels.


## LEDs
Whilst the IC itself has no LEDs, many breakout boards/modules with the chip have LEDs. These are typically wired to the INA3221’s open-drain alert pins (plus one "power" LED).  The usually have silkscreened labels, and indicate:
- Power LED – just shows the board has VS power. Some boards even have a solder jumper to disable it.
- CRI / "Critical" LED – lights when any enabled channel’s instantaneous shunt reading exceeds the programmed Critical-Alert limit. Active-low (the pin sinks current when tripped).
- WRN / "Warning" LED – lights when the averaged shunt reading exceeds the Warning-Alert limit (depends on your averaging setting). Also active-low.
- PV / "Power-Valid" LED – indicates whether all bus voltages are inside the programmable PV window. The PV pin is open-drain pulled up via VPU; "valid" releases high, "invalid" pulls low. Default PV window is ~9–10 V until changed see `set-valid-power-upper-limit` and `set-valid-power-lower-limit`  in the driver.
- TC / "Timing-Control" LED – lights if the power-up sequencing between rails violates the timing rules (e.g., a rail didn’t reach ~1.2 V in time). Active-low.

### Why a PV (or other) LED might seem "wrong"
Unused channels: PV checks all three bus voltages. If any unused channel is floating, PV will read "invalid" and keep the LED on. Tie unused IN− to a used rail (and float IN+) or disable conversions for that channel / widen the PV window.
Open-drain logic: These pins pull low on fault; many boards wire LEDs so "on = fault." This is expected behaviour.
Limits not set / out of range: CRI/WRN default to "disabled" (full-scale). Program the 13-bit limit fields (bits 15–3, LSB = 40 uV across the shunt) and make sure you enable the alert bits/masks

## Conversion time & averaging (how long to wait)
For a "both" conversion cycle:  Update time = (CTshunt + CTbus) × averages × (# enabled channels).

## Measurement functions (driver)
- read-shunt-voltage (given a channel)
- read-bus-voltage (given a channel)
- read-current (given a channel)
- read-power (given a channel)
- set-shunt-resistor - specification of shunt resistors (per-channel)
- ...see the code for complete content.

## What is not implemented?
- Timing Control: The INA3221’s Timing-Control (TC) alert is very specific: at power-up (or immediately after a software reset) it watches for CH1 bus to reach 1.2 V, then demands that CH2 bus also reaches ≥ 1.2 V within ~28.6 ms (four complete conversion cycles at the default power-up timing).  If CH2 misses that window, the TC pin pulls LOW and the TCF flag records the failure. (Changing the Configuration register before the sequence finishes disables this feature for that boot.)  Currently this driver is designed for typical current/power logging.  TC is a boot-only check and is disabled if the Configuration is set too early.  The Power-Valid window and Critical/Warning alerts are more generally useful during normal operation.

## Compatibility notes of INA3221 vs INA226
- INA3221 has no calibration register - current/power must be calculated in the driver.
- Register data values are stored left-justified by 3 bits.
- INA3221 adds 'Power-Valid' window and Summation features not present on INA226.
