# Toit Library for the TI INA3221 Triple-Channel Voltage/Current Monitor IC
Toit driver for the INA3221: three channels of shunt + bus voltage monitoring
 with alerts. Unlike INA226, there is no calibration register— current is
 computed in software from Vshunt and shunt resistor values.

## About the Device
The INA3221 from Texas Instruments is a precision digital power monitor IC with
 an integrated 16-bit ADC.  It measures the voltage drop across a shunt resistor
 to calculate current, monitors the bus voltage directly, and internally
 multiplies the two to report power consumption.

## Quick Start Information
Use the following steps to get operational quickly:
- Follow Wiring Diagrams to get the device connected correctly.
- Ensure Toit is installed on the ESP32 and operating.  (Most of the code
  examples require the use `jag monitor` to show outputs.)  See Toit
  Documentation to [get started](https://docs.toit.io/getstarted).
- This is a device using I2C, Toit documentation has a great [I2C
  introduction](https://docs.toit.io/tutorials/hardware/i2c).
- Use one of the code examples to see the driver in operation.

## Core Features
- Channels: 3 (independent enable; common timing/mode).
- Shunt voltage: ±163.84 mV full-scale, 40 uV/LSB. Data are left-justified in
  bits 14..3; right-shift by 3 before scaling.
- Bus voltage: 0–26 V input (coding to 32.76 V), 8 mV/LSB
- Current & power: no current/power registers. Computed in this driver using: I
  = Vshunt / Rshunt, P = Vbus × I.
- Conversion times: 140 us … 8.244 ms + averaging (1…1024).
- Operating modes: continuous and single-shot (triggered) that measures all
  enabled channels once then returns to power-down; separate power-down mode
  with ~40 us recovery.
- Supply current: 350 uA typ (active), 0.5 uA typ (power-down).
- I²C / SMBus: four programmable addresses (A0 pin).
- Alerts: Critical/Warning (per-channel overcurrent via shunt), Power-Valid
  window (all bus voltages between upper/lower limits), Timing Control and
  Summation alerts.
- Max measurable current is 0.16384 V / Rshunt.

> [!WARNING]
> There are two main variations of module both with different wiring
> requirements (ADD PICTURES AND DESCRIBE)

### Comparison of Sibling Models
Given their similarity, driver library for sibling models were written at the same time:
| Model | [**INA219**](https://github.com/milkmansson/toit-ina219) | [**INA226**](https://github.com/milkmansson/toit-ina226/) | [**INA3221**](https://github.com/milkmansson/toit-ina3221/) (This driver)|
| ---- | ---- | ---- | ---- |
| **Channels** | 1 | 1 | 3 (independent but require a common GND and other wiring caveats, see Datasheet.) |
| **Bus/common-mode range** | 0–26 v(bus/common-mode). Bus register full-scale can be configured at 16v or 32v, with caveats (BRNG). | 0–36v common-mode. Bus register full-scale 40.96v but cannot exceed 36v at pins. | 0–26v common-mode; bus register full scale to 32.76v, but input cannot exceed 26v. |
| **Shunt Voltage** | 320mv, depending on PGA config | +/-81.92mv fixed |
| **Device Voltage** | 3.0-5.5 v| 2.7-5.5v | 2.7-5.5v |
| **Averaging options**  | 8 fixed options between 1 and 128.  Averaging and Conversion times are fixed to a limited set of pairs and cannot be set separately. | Several options between 1 and 1024.  All options available in combination with all conversion time options.  | Several options between 1 and 1024.  All options available in combination with all conversion time options. |
| **Current & power registers** | Present (Requires device calibration, performed by the driver) | Present (Requires calibration, performed by the driver)  | Reports shunt & bus per channel but current and power are calulated in software by the driver. |
| **ADC / resolution**  | 9 to 12-bit depending on the register, and averaging/ sampling option selected. | 16-bit | 13-bit |
| **Alerting/Alert pin** | None. "Conversion Ready" exists, but must be checked in software. | Alerts and Alert Pin, but different features from INA3221. | Alerts and Alert pin, but different features from INA226  |
| **Possible I2C addresses** | 16 | 16 | 4 |
| **Datasheets** | [INA219 Datasheet](https://www.ti.com/lit/gpn/INA219) | [INA226 Datasheet](https://www.ti.com/lit/gpn/INA226) | [INA3221 Datasheet](https://www.ti.com/lit/ds/symlink/ina3221.pdf) |
| **Other Notes** | - | - | Has no calibration register - current/power must be calculated in the driver.  Adds 'Power-Valid' window and Summation features.

## Core Concepts

### "Shunt" History
"Shunt" comes from the verb to shunt, meaning to divert or to bypass.  In
railway terms, a shunting line diverts trains off the main track.  In electrical
engineering, a shunt resistor is used to divert current into a measurable path.

Originally, in measurement circuits, shunt resistors were used in analog
ammeters.  A sensitive meter with sensitive needle movement could only handle
very tiny current.  A low-value "shunt" resistor was therefore placed in
parallel to bypass (or shunt) most of the current, so the meter only saw a safe
fraction.  By calibrating the ratio, large currents could be read with a
small meter.

### How it works
The INA219 measures current using a tiny precision resistor (referred to as the
shunt resistor), which is placed in series with the load.  When current flows
through the shunt, a small voltage develops across it.  Because the resistance
is very low (e.g., 0.1 Ohm), this voltage is only a few millivolts even at
significant currents. The INA219’s ADC is designed to sense this tiny voltage
drop, precision in the microvolt range.  Ohm’s Law (V = I × R) is used to
compute current.

Simultaneously, the device monitors the bus voltage on the load side of the
shunt. By combining the shunt voltage (for current) with the bus voltage (for
supply level), the INA219 can also compute power consumption.  The INA219 stores
these values in its registers which the driver retrieves using I2C.

# Usage

## Measuring/Operating Modes
The device has two measuring modes: Continuous and Triggered, as well as
combinations of measuring both the bus and shunt voltage. (Use
`set-measure-mode` to configure these.) Alongside, `set-measure-mode
MODE-POWER-DOWN` will turn the device off.

### Continuous Mode
In continuous modes `MODE-BUS-CONTINUOUS`, `MODE-SHUNT-CONTINUOUS` and
`MODE-SHUNT-BUS-CONTINUOUS` the INA219 loops forever:
- It repeatedly measures bus voltage and/or shunt voltage.
- Each conversion result overwrites the previous one in the registers.
- The sampling cadence is set using conversion times and averaging settings.

Use cases:
- Requiring a live stream of current/voltage/power, e.g. logging consumption of
  an IoT node over hours.
- In cases where the MCU needs to poll for measurements periodically, & expects
  the register to always hold the freshest value.
- Best for steady-state loads or long-term monitoring.

### Triggered Mode
In triggered (single-shot) modes `MODE-SHUNT-TRIGGERED`, `MODE-BUS-TRIGGERED`,
and `MODE-SHUNT-BUS-TRIGGERED`:
- The INA219 sits idle until a measurement is explicitly triggered (by writing
  to the config register).
- It performs exactly one set of conversions (bus + shunt, with averaging if
  configured).
- Then it goes back to idle (low power).

Use cases:
- Low power consumption: e.g. wake up the INA219 once every few seconds/minutes,
  take a measurement, then let both the INA219 and MCU sleep.
- Synchronized measurement: e.g. where a measurement is necessary at the same
  time a load is toggled, eg, so the measurement can be triggered at the right
  time after.
- Useful in battery-powered applications where quiescent drain must be
  minimized.

### Power-Down
INA219 can enter an ultra-low-power state. In this state, no measurements
happen.  Supply current drops to 0.5 uA typ (2uA max). Useful for ultra-low
power systems where periodic measurement isn't needed. Use `set-measure-mode
MODE-POWER-OFF` to shutdown.  Start again by setting the required measure mode
using `set-measure-mode MODE-TRIGGERED` or `set-measure-mode MODE-CONTINUOUS`

## Features

### Valid Power
These two registers contains upper and lower values used to determine if
'power-valid' conditions are met.  PV is not a 'is it between lower and upper'
window check.  PV (Power-Valid) works with hysteresis:
  - PV goes valid (PV pin = high) only after ***all three channel*** bus voltages have
    first risen above the upper limit.  Power on default for upper limit is 10.0
    V
    - If a channel, is not in use, tie its IN− to a used rail and leave IN+
      floating, or PV will never declare 'valid'.  It is not enough to simply
      disable the channel in the configuration.
  - Once valid, it stays valid until ***any individual channel*** bus voltage falls below
    the lower limit, then PV goes low (invalid).   Power on default for lower
    limit is 9.0 V

### Critical and Warning Alerts
> “The warning alert and critical alert functions allow for independent
> threshold monitoring on each channel. The critical alert function takes
> precedence over the warning alert. [INA3221 Datasheet, pp29]

Both limits differ slightly:
#### Warning Alerts:
Warning Alert monitor the **averaged value** of each shunt-voltage channel. The
averaged value of each shunt-voltage channel is based on the number of averages
set with `set-sampling-rate`.  (The average value updates each time there is a
conversion on the corresponding channel.)  This also means if there are no
conversions, the alert will not trip.  Use the feature with:
```
ina3221-driver.set-sampling-rate Ina226.AVERAGE-128-SAMPLES
ina3221-driver.set-warning-alert-threshold --voltage=xxx --channel=<Channel #>
// OR
ina3221-driver.set-warning-alert-threshold --current=xxx --channel=<Channel #>
```
Note that these two functions use the same register, the driver handles the math
and sets the value in the register appropriately.  Setting either current or
voltage clears the previous configuration.  If the pin alerts, determine which
channel alerted using `warning-alert-channel`:
```
print "Critical alert triggere on channel: $(critical-alert-channel)"
```
To configure latching for warning alerts, use `enable-warning-alert-latching`
and `disable-warning-alert-latching`.  (Setting is for all channels at once.)

#### Critical Alerts:
Critical Alerts monitors **each individual conversion** of each shunt-voltage
channel.  The feature compares these to the configured critical-alert limit for
each channel and triggers if the limit is exceeded.  (If there are no
conversions, the alert will not trip.) Use the feature with:
```
ina3221-driver.set-critical-alert-threshold --voltage=xxx --channel=<Channel #>
// OR
ina3221-driver.set-critical-alert-threshold --current=xxx --channel=<Channel #>
```
Note that these two functions use the same register, the driver handles the
math and sets the value in the register appropriately.  Setting either current
or voltage clears the previous configuration.  If the pin alerts, determine
which channel alerted using `critical-alert-channel`:
```
print "Critical alert triggere on channel: $(critical-alert-channel)"
```
To configure latching for critical alerts, use `enable-critical-alert-latching`
and `disable-critical-alert-latching`.  (Setting is for all channels at once.)

### Sampling Rate
The sampling rate determines how often the device samples and averages the input
 signals (bus voltage and shunt voltage) before storing them in the result
 registers.  More samples lead to more stable values, but can lengthen the time
 required for a single measurement.  This is configured using one of the
 register code/enum values, not actual rate:

| **Configuration Constant** | **Explanation**|
| - | - |
| AVERAGE-1-SAMPLE | 1 sample = no averaging (Default) |
| AVERAGE-4-SAMPLES | Values averaged over 4 samples. |
| AVERAGE-16-SAMPLES | Values averaged over 16 samples. |
| AVERAGE-64-SAMPLES | Values averaged over 64 samples. |
| AVERAGE-128-SAMPLES | Values averaged over 128 samples. |
| AVERAGE-256-SAMPLES | Values averaged over 256 samples. |
| AVERAGE-512-SAMPLES | Values averaged over 512 samples. |
| AVERAGE-1024-SAMPLES |  Values averaged over 1024 samples. |

Use these by something like:
```
ina3221-driver.set-sampling-rate Ina226.AVERAGE-128-SAMPLES
```

### Shunt Summation
This is the sum of the single conversion shunt voltages of the enabled channels.
This register is updated with the most recent sum after all selected channels
have completed a new conversion.
- Enable channels for summation using `enable-summation --channel=<Channel #>`.
- Disable channels for summation using `disable-summation --channel=<Channel
  #>`.
- Query if summation is enabled for a channel using `channel-summation-enabled
  --channel=<Channel #>`
- Read current shunt summation value using `read-shunt-summation --voltage` and
  `read-shunt-summation --current`.

### LEDs
Whilst the IC itself has no LEDs, many breakout boards/modules with the chip
have LEDs. These are typically wired to the INA3221’s open-drain alert pins
(plus one "power" LED).  The usually have silkscreened labels, and indicate:
- Power LED – just shows the board has VS power. Some boards have a solder
  jumper to disable it.
- CRI / "Critical" LED – lights when any enabled channel’s instantaneous shunt
  reading exceeds the programmed Critical-Alert limit. Active-low (the pin sinks
  current when tripped).
- WRN / "Warning" LED – lights when the averaged shunt reading exceeds the
  Warning-Alert limit (depends on your averaging setting). Also active-low.
- PV / "Power-Valid" LED – indicates whether all bus voltages are inside the
  programmable PV window. The PV pin is open-drain pulled up via VPU; "valid"
  releases high, "invalid" pulls low. Default PV window is ~9–10 V until changed
  see `set-valid-power-upper-limit` and `set-valid-power-lower-limit`  in the
  driver.
- TC / "Timing-Control" LED – lights if the power-up sequencing between rails
  violates the timing rules (e.g., a rail didn’t reach ~1.2 V in time).
  Active-low.

#### Why a PV (or other) LED might seem "wrong"
PV checks all three bus voltages. If any unused channel is floating, PV will
read "invalid" and keep the LED on. Tie unused IN− to a used rail (and float
IN+) or disable conversions for that channel / widen the PV window.  Open-drain
logic: These pins pull low on fault; many boards wire LEDs so "on = fault." This
is expected behaviour.  Limits not set / out of range: CRI/WRN default to
"disabled" (full-scale). Program the 13-bit limit fields (bits 15–3, LSB = 40 uV
across the shunt) and make sure you enable the alert bits/masks

### Conversion time & averaging (how long to wait)
For a "both" conversion cycle:  Update time = (CTshunt + CTbus) × averages × (#
enabled channels).  This estimate is used as a maximum wait time for a
`trigger-measurement --wait` iteration.

### Measurement functions (driver)
- `read-shunt-voltage`: The voltage drop across the shunt: Vshunt = IN+ − IN−.
  Given in Volts
- `read-bus-voltage`: The "load node" voltage. If VBUS is not tied to IN−, the
  function returns whatever VBUS is wired to.  Given in Volts.
- `read-supply-voltage`: The upstream/source voltage *before* the shunt
  (Vsupply ≈ Vbus + Vshunt = (voltage at IN−) + (IN+ − IN−) = voltage at IN+.
  Given in Volts.
- `read-shunt-current`: The current through the shunt and load load, in amps.
  Internally, the chip uses a calibration constant set from the configured shunt
  resistor value. Given in Amps. Caveats:
  - Accurate only if shunt value in code matches the physical shunt.
  - Choose appropriate averaging/conversion time for scenario.
- `read-load-power`: Power delivered to the load, in watts. Caveats:
  - Because Vbus is after the shunt, this approximates power at the load (not at
  the source).
  - Depends on correct calibration.  (Calibration values are care of in this
    driver when setting `set-shunt-resistor`, and set to 0.100 Ohm by default).

## Changing the Shunt Resistor
Many modules ship with 0.1 Ohm or 0.01 Ohm shunts.
- For high-current applications (tens of amps), the shunt can be replaced with a
  much smaller value (e.g. 1–5 mOhm). This reduces voltage drop and wasted power,
  and raises the maximum measurable current, but makes the resolution for tiny
  currents coarser.
- For low-current applications (milliamps), a larger shunt (e.g. 0.5–1.0 Ohm)
  increases sensitivity and resolution, but lowers the maximum measurable
  current (80 mA with a 1 Ohm shunt) and burns more power in the resistor
  itself.

> [!IMPORTANT]
> If the shunt is changed, always add a line to the beginning of the code to
> set the shunt resistor value every boot.  The INA3221 cannot detect it, and
> the driver does not store these values permanently.

### Shunt Resistor Values
The following table illustrates consequences to current measurement with some
sample shunt resistor values:

Shunt Resistor (SR) | Max Measurable Current | Shunt Resistor Wattage Requirement  | Resolution per bit | Note
-|-|-|-|-
1.000 Ohm	| 163.84 mA | >0.125w | 40 uA/bit | Great for small currents, higher drop.
0.100 Ohm (default) | 1.638 A | 0.268 W (use > .5 W) | 0.4 uA/bit | Common R100 resistor on modules; good for general range.
0.050 Ohm | 3.2768 A | use > 1W | 0.8 mA/bit | Watch copper and heating.
0.010 Ohm | 16.384 A | use 3-5 W | 4 mA/bit | High current, typically needs beefy external shunt.

## Not implemented
### Timing Control
The INA3221’s Timing-Control (TC) alert is very specific feature: at power-up
 (or immediately after a software reset) it watches for CH1 bus to reach 1.2 V,
 then checks to see that that CH2's bus also reaches ≥ 1.2 V, within 28.6 ms
 (four complete conversion cycles at the default power-up timing).  If CH2
 misses that window, the TC pin alerts low, and the TCF flag sets, recording the
 failure.  (Changing the Configuration register before the sequence finishes
 essentially disables this feature for that boot.)  Currently this driver is
 designed for typical current/power logging.  TC is a boot-only check and is
 disabled if the Configuration is set too early.  The Power-Valid window and
 Critical/Warning alerts are more generally useful during normal operation.

## Issues
If there are any issues, changes, or any other kind of feedback, please
[raise an issue](toit-ina3221/issues). Feedback is welcome and appreciated!

## Disclaimer
- This driver has been written and tested with an unbranded INA226 module.
- All trademarks belong to their respective owners.
- No warranties for this work, express or implied.

## Credits
- [Florian](https://github.com/floitsch) for the tireless help and encouragement
- The wider Toit developer team (past and present) for a truly excellent product
- AI has been used for code and text reviews, analysing and compiling data and
  results, and assisting with ensuring accuracy.

## About Toit
One would assume you are here because you know what Toit is.  If you dont:
> Toit is a high-level, memory-safe language, with container/VM technology built
> specifically for microcontrollers (not a desktop language port). It gives fast
> iteration (live reloads over Wi-Fi in seconds), robust serviceability, and
> performance that’s far closer to C than typical scripting options on the
> ESP32. [[link](https://toitlang.org/)]
- [Review on Soracom](https://soracom.io/blog/internet-of-microcontrollers-made-easy-with-toit-x-soracom/)
- [Review on eeJournal](https://www.eejournal.com/article/its-time-to-get-toit)
