# Technical Report: Raspberry Pi & Arduino Alarm System

## 1. Introduction
This report documents the implementation of an alarm system developed for two distinct architectures:
1.  **Raspberry Pi 4**: Implemented in ARM64 Assembly language (`alarm_inverted.S`).
2.  **Arduino**: Implemented in C++ (`main.ino`).

In both implementations, the system interfaces with a Push Button, PIR Motion Sensor, LED, and Active Buzzer. Use of Active Low logic and Software PWM is consistent across both platforms.

## 2. Raspberry Pi Implementation (ARM64 Assembly)

### 2.1 Hardware Interface
The program interacts with the hardware using **Memory Mapped GPIO**. Instead of using slow file-based sysfs calls, the program maps the Raspberry Pi's GPIO physical memory address range into its virtual memory space.

*   **Target Device**: `/dev/gpiomem` (Allows non-root GPIO access if permissions allow, though `sudo` is often used).
*   **Base Address**: `0xFE200000` (Raspberry Pi 4 BCM2711 peripheral base).
*   **Page Size**: 4KB (Standard system page size).

### 2.2 Pin Configuration
| Component | GPIO Pin | Register | Function Selection | Logic |
| :--- | :---: | :---: | :---: | :--- |
| **LED** | GPIO 17 | `GPFSEL1` | Output (001) | Active High |
| **Buzzer** | GPIO 22 | `GPFSEL2` | Output (001) | **PWM Modulated** |
| **Button** | GPIO 23 | `GPFSEL2` | Input (000) | **Active Low** |
| **Sensor** | GPIO 24 | `GPFSEL2` | Input (000) | **Active Low** |

### 2.3 Algorithm and Logic

#### Initialization Phase
1.  **File Open**: The program uses `openat` (syscall 56) to open `/dev/gpiomem`.
2.  **Memory Map**: It uses `mmap` (syscall 222) to map 4096 bytes at offset 0. This gives a pointer (saved in register `x19`) to the start of the GPIO registers.
3.  **Configuration**:
    *   **GPFSEL1**: Bits for GPIO 17 are cleared and set to `001` (Output).
    *   **GPFSEL2**: Bits for GPIO 22 are set to `001` (Output). Bits for GPIO 23 and 24 are cleared to `000` (Input).

#### Main Polling Loop
The system enters an infinite loop to monitor inputs.
*   **Register Read**: It reads the `GPLEV0` (GPIO Level 0) register, which contains the current state of pins 0-31.
*   **Bit Masking**: It uses the TST (Test) instruction to check bit 23 and bit 24.
*   **Active Low Logic**:
    *   Standard logic usually checks for HIGH (1).
    *   This implementation checks for **LOW (0)** using the `b.eq` (Branch if Equal to 0) instruction.
    *   This logic assumes the sensors pull the line to Ground (0V) when triggered.

#### Logic Inversion Rationale
During testing, it was observed that the "Standard" (Active High) logic caused the alarm to trigger continuously immediately upon running. This occurred because:
1.  **Floating Inputs**: The GPIO pins, when not actively driven to Ground, often float to a "High" state due to internal pull-up resistors or electrical interference.
2.  **Module Behavior**: Many sensor and button modules are designed as "Active Low". They output a High signal (VCC) when idle and pull the signal to Ground (Low) when triggered.

To correct this, the logic was **inverted** in `alarm_inverted.S`. Instead of waiting for the bit to become `1` (High), the program now waits for the bit to become `0` (Low), ensuring the alarm only triggers when the button is pressed or motion is detected.

#### Alarm Trigger & Volume Control
When a trigger is detected, the system executes an alarm sequence 5 times.

**Software PWM (Pulse Width Modulation)**:
To reduce the buzzer volume without external resistors, the code implements a software-based PWM loop instead of a constant signal.

*   **Signal**: 100 Hz (approx).
*   **Period**: 10ms.
*   **Duty Cycle**: 10% (1ms ON, 9ms OFF).
*   **Implementation**:
    1.  Turn Buzzer **ON** (Write to `GPSET0`).
    2.  Sleep **1ms**.
    3.  Turn Buzzer **OFF** (Write to `GPCLR0`).
    4.  Sleep **9ms**.
    5.  Repeat 50 times (Total duration: 0.5 seconds).

This fast switching is audible as a continuous tone but with reduced effective energy (lower volume).

#### Timing
Timing is handled by the `nanosleep` syscall (101). Two `timespec` structures are defined in the data section:
*   `ts_pwm_on`: 1,000,000 ns (1ms)
*   `ts_pwm_off`: 9,000,000 ns (9ms)
*   `ts_500ms`: 500,000,000 ns (Silence phase)

## 3. Arduino Implementation (C++)

The system was also implemented on an Arduino platform using C++. This implementation mirrors the functionality of the Raspberry Pi assembly version, proving the portability of the logic (Active Low inputs, PWM buzzers) across different architectures.

### 3.1 Hardware Interface
Unlike the Raspberry Pi implementation which requires manual handling of memory-mapped GPIO registers, the Arduino implementation utilizes the standard Arduino Core API to interact with the ATmega328P (or similar) microcontroller registers abstraction.

*   **Active Low Inputs**: The built-in `INPUT_PULLUP` mode is used for buttons and sensors, eliminating the need for external resistors.
*   **PWM Output**: Manual timing loops (bit-banging) are used to replicate the specific duty cycle and frequency of the Assembly version, though `analogWrite` is also an option on PWM pins.

### 3.2 Pin Configuration
| Component | Arduino Pin | Mode | Logic |
| :--- | :---: | :---: | :--- |
| **LED** | D13 | OUTPUT | Active High |
| **Buzzer** | D9 | OUTPUT | **PWM Modulated** |
| **Button** | D2 | INPUT_PULLUP | **Active Low** |
| **Sensor** | D3 | INPUT_PULLUP | **Active Low** |

### 3.3 Algorithm and Logic

#### Initialization (`setup`)
The `setup()` function configures the hardware:
1.  **Inputs**: Pins D2 and D3 are set to `INPUT_PULLUP`. This enables the internal pull-up resistors, holding the lines HIGH (Logic 1) when idle.
2.  **Outputs**: Pins D13 and D9 are set to `OUTPUT` and initialized to LOW (OFF).

#### Main Loop (`loop`)
The `loop()` function continuously monitors the inputs:
*   It reads `digitalRead(BUTTON_PIN)` and `digitalRead(SENSOR_PIN)`.
*   Since the inputs are Active Low, the logic checks if either pin reads `LOW` (0).
*   If a trigger is detected, the `triggerAlarm()` function is called.

#### Alarm Structure
The alarm sequence is identical logic-wise to the Raspberry Pi:
*   **Cycles**: The alarm runs for 5 iterations.
*   **Pattern**:
    1.  **LED ON**: `digitalWrite(LED_PIN, HIGH)`
    2.  **Buzzer ON (PWM)**: A loop toggles the buzzer pin HIGH for 1ms and LOW for 9ms (10% duty cycle) for 50 iterations. This creates a lower-volume tone compared to a constant 5V signal.
    3.  **LED OFF**: `digitalWrite(LED_PIN, LOW)`
    4.  **Silence**: A 500ms delay (`delay(500)`).

## 4. Conclusion
The implementation demonstrates hardware control across two very different levels of abstraction:
1.  **Lowest Level (Assembly/RPi)**: Direct memory manipulation, syscalls, and CPU instructions. Provides maximum control and understanding of the hardware architecture.
2.  **High Level (C++/Arduino)**: Abstracted API usage (`digitalWrite`, `pinMode`). Provides rapid development and portability.

Both implementations successfully manage real-time constraints (PWM generation) and sensor logic (Active Low handling), ensuring a reliable alarm system.
