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
