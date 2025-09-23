# Toit Library for the TI INA3221 Triple-Channel Voltage/Current Monitor IC
Toit driver for the INA3221: three channels of shunt + bus voltage monitoring with alerts. Unlike INA226, there is no calibration register— current is computed in software from Vshunt and shunt resistor values.

## About the Device
The INA3221 from Texas Instruments is a precision digital power monitor IC with an integrated 16-bit ADC.  It measures the voltage drop across a shunt resistor to calculate current, monitors the bus voltage directly, and internally multiplies the two to report power consumption.  

- Channels: 3 (independent enable; common timing/mode). 
- Shunt voltage: ±163.84 mV full-scale, 40 µV/LSB. Data are left-justified in bits 14..3; right-shift by 3 before scaling. 
- Bus voltage: 0–26 V input (coding to 32.76 V), 8 mV/LSB; also left-justified (>>3). 
- Current & power: no current/power registers. Computed in this driver using: I = Vshunt / Rshunt, P ≈ Vbus × I.
- Conversion times: 140 µs … 8.244 ms + averaging (1…1024). 
- Operating modes: continuous and single-shot (triggered) that measures all enabled channels once then returns to power-down; separate power-down mode with ~40 µs recovery. 
- Supply current: 350 µA typ (active), 0.5 µA typ (power-down). 
- I²C / SMBus: four programmable addresses (A0 pin). 
- Alerts: Critical/Warning (per-channel overcurrent via shunt), Power-Valid window (all bus voltages between upper/lower limits), Timing Control and Summation alerts.
- Max measurable current is 0.16384 V / Rshunt. 

## Wiring
There are two main variations of module both with different wiring requirements (ADD PICTURES AND DESCRIBE)

## Measuring / operating modes
- Continuous: device cycles shunt→bus for each enabled channel in order. Registers update after averaging. 
- Single-shot/Triggered: Once triggered, the chip converts every enabled channel once, then enters power-down. 
- Power-down: lowest quiescent; registers keep last values; 40 µs recovery time to activate. 

## Conversion time & averaging (how long to wait)
For a “both” conversion cycle:  Update time = (CTshunt + CTbus) × averages × (# enabled channels). 

## Measurement functions (driver)
- read-shunt-voltage (given a channel)
- read-bus-voltage (given a channel)
- read-current (given a channel)
- read-power (given a channel)
- set-shunt-resistor - specification of shunt resistors (per-channel)

## Compatibility notes of INA3221 vs INA226
- INA3221 has no calibration register - current/power must be calculated in the driver.
- Register data values are stored left-justified by 3 bits. 
- INA3221 adds 'Power-Valid' window and Summation features not present on INA226. 
