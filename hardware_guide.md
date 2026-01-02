# Hardware Setup Guide - Alarm System

This guide details the components and wiring required to run the `alarm.S` program on a **Raspberry Pi 4 Model B**.

> [!IMPORTANT]
> **Logic Level**: The assembly code expects **Active High** inputs. This means the pins must read **3.3V (Logic 1)** to trigger the alarm. You MUST use **Pull-Down Resistors** (to Ground) for the button to ensure it reads 0V when not pressed.

## Component List

| Component | Quantity | Description |
| :--- | :---: | :--- |
| **Raspberry Pi 4** | 1 | Model B (or 3B+, but change address in code if 3B+) |
| **Breadboard** | 1 | Half-size or full-size |
| **Jumper Wires** | 10+ | Male-to-Male (M-M) and Male-to-Female (M-F) |
| **LED** | 1 | Any color (Red recommended for alarm) |
| **Resistor (LED)** | 1 | 220Ω or 330Ω (Protects the LED) |
| **Active Buzzer** | 1 | 3V-5V Active Buzzer (Generates sound when powered) |
| **Push Button** | 1 | Tactile switch (4-pin or 2-pin) |
| **Resistor (Button)**| 1 | 10kΩ (For Pull-Down) |
| **Motion Sensor** | 1 | **HC-SR501** PIR Motion Sensor (Recommended) |

## GPIO Pinout Reference

The code uses **BCM (Broadcom) GPIO Numbers**. Here is the mapping to the Physical Board Pins on the Raspberry Pi:

| BCM GPIO | Physical Pie Pin | Function | Direction |
| :---: | :---: | :--- | :--- |
| **GPIO 17** | **Pin 11** | LED | Output |
| **GPIO 22** | **Pin 15** | Buzzer | Output |
| **GPIO 23** | **Pin 16** | Push Button | Input |
| **GPIO 24** | **Pin 18** | Sensor | Input |
| **GND** | **Pin 6, 9, 14, etc.** | Ground | - |
| **3.3V** | **Pin 1, 17** | Power | - |
| **5V** | **Pin 2, 4** | Power (for Sensor) | - |

## Step-by-Step Wiring Instructions

**Ensure the Raspberry Pi is POWERED OFF while building the circuit.**

### 1. LED (Output) - GPIO 17
1.  Connect the **Long Leg (+) / Anode** of the LED to **Physical Pin 11 (GPIO 17)**.
2.  Connect the **Short Leg (-) / Cathode** to one leg of a **220Ω/330Ω Resistor**.
3.  Connect the other leg of the Resistor to a **GND (Ground)** rail on the breadboard.
4.  Connect the GND rail to a Ground pin on the Pi (e.g., Physical Pin 6).

### 2. Buzzer (Output) - GPIO 22
*Assuming a generic low-power active buzzer.*
1.  Connect the **Positive (+)** pin of the Buzzer to **Physical Pin 15 (GPIO 22)**.
2.  Connect the **Negative (-)** pin of the Buzzer to the **GND** rail.

### 3. Push Button (Input) - GPIO 23
**You have a 3-Pin Module (Pins: S, V, G)**
*   **S (Signal)**: Connect to **Physical Pin 16 (GPIO 23)**. *(User Color: Blue)*
*   **V (VCC)**: Connect to **3.3V** (Physical Pin 1).
*   **G (GND)**: Connect to **GND** rail.
*   *Note*: Ensure the module outputs HIGH when pressed. If it outputs LOW, the code logic will need to be inverted.

**If using a raw 2-pin/4-pin switch:**
*Requires a Pull-Down configuration so it stays LOW (0V) until pressed.*
1.  Place the Push Button on the breadboard.
2.  Connect **One Side** of the button to **3.3V Power** (Physical Pin 1).
3.  Connect the **Other Side** of the button to **Physical Pin 16 (GPIO 23)**.
4.  **Crucial Step**: Connect a **10kΩ Resistor** from the **Same Side (Pin 16 side)** of the button to **GND**.
    *   *Result*: When open, Resistor pulls pin to GND (0). When pressed, direct connection overpowers resistor and pulls pin to 3.3V (1).

### 4. Motion Sensor (HC-SR501) - GPIO 24
1.  **VCC**: Connect to **5V Power** (Physical Pin 2 or 4). *PIRs usually need 5V input.*
2.  **GND**: Connect to **GND**.
3.  **OUT / Signal**: Connect to **Physical Pin 18 (GPIO 24)**.
    *   *Note*: HC-SR501 output is typically 3.3V logic compatible (High when motion detected), which is perfect for the Pi.

## Circuit Diagram (Text Representation)

```mermaid
graph TD
    subgraph Raspberry Pi 4
        P11[GPIO 17 (Pin 11)]
        P15[GPIO 22 (Pin 15)]
        P16[GPIO 23 (Pin 16)]
        P18[GPIO 24 (Pin 18)]
        GND[Ground Pin]
        3V3[3.3V Pin]
        5V[5V Pin]
    end

    subgraph Actuators
        LED
        Buzzer
    end

    subgraph Sensors
        Button
        PIR[PIR Motion Sensor]
    end

    P11 -->|+ Leg| LED
    LED -->|- Leg| Resistor220
    Resistor220 --> GND

    P15 -->|+ Leg| Buzzer
    Buzzer -->|- Leg| GND

    3V3 -->|Side A| Button
    Button -->|Side B| P16
    P16 -->|Pull-Down 10k| Resistor10k
    Resistor10k --> GND

    5V --> VCC[PIR VCC]
    GND --> GND_PIR[PIR GND]
    PIR_OUT[PIR Output] --> P18
```

## Summary Checklist

- [ ] LED Long leg to GPIO 17?
- [ ] LED Short leg to Resistor -> Ground?
- [ ] Buzzer (+) to GPIO 22?
- [ ] Button connects 3.3V to GPIO 23 when pressed?
- [ ] Button has 10kΩ resistor pulling GPIO 23 to Ground?
- [ ] Sensor Out connects to GPIO 24?
