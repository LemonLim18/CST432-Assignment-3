/*
 * Alarm System (Active Low Inputs) with PWM Volume Control
 * Converted from Raspberry Pi 4 ARM64 Assembly to Arduino
 *
 * Original: main.S (ARM64 Assembly for Raspberry Pi 4)
 * 
 * Pin Mapping (RPi GPIO → Arduino):
 *   - Button: GPIO 23 → D2 (Active LOW with internal pull-up)
 *   - Sensor: GPIO 24 → D3 (Active LOW with internal pull-up)
 *   - LED:    GPIO 17 → D13 (Output)
 *   - Buzzer: GPIO 22 → D9 (PWM Output)
 *
 * How it works:
 *   1. Monitors button (D2) and sensor (D3) continuously
 *   2. When either goes LOW (triggered), starts alarm
 *   3. Alarm cycles 5 times: LED ON + Buzzer PWM, then LED OFF + silence
 *   4. PWM controls buzzer volume (10% duty cycle = quieter)
 */

// ============ PIN DEFINITIONS ============
// These correspond to the Raspberry Pi GPIO pins in the original assembly
const int BUTTON_PIN = 2;   // Was GPIO 23 on RPi - Active LOW input
const int SENSOR_PIN = 3;   // Was GPIO 24 on RPi - Active LOW input
const int LED_PIN = 13;     // Was GPIO 17 on RPi - Output
const int BUZZER_PIN = 9;   // Was GPIO 22 on RPi - PWM Output

// ============ TIMING CONSTANTS ============
// Converted from the assembly's nanosleep timespec values
const int ALARM_CYCLES = 5;         // Number of alarm cycles (was x20 = #5)
const int PWM_ITERATIONS = 50;      // 50 iterations × 10ms = 500ms total
const int PWM_ON_TIME_US = 1000;    // 1ms ON (ts_pwm_on: 1,000,000 ns)
const int PWM_OFF_TIME_US = 9000;   // 9ms OFF (ts_pwm_off: 9,000,000 ns)
const int SILENCE_DELAY_MS = 500;   // 0.5s silence (ts_500ms)

// ============ SETUP ============
// Equivalent to the GPIO configuration in assembly (_start section)
void setup() {
  // Configure INPUT pins with internal pull-up resistors
  // Assembly used: ldr/str to GPFSEL registers, inputs default to 000
  // Arduino: INPUT_PULLUP enables internal pull-up, making pins Active LOW
  pinMode(BUTTON_PIN, INPUT_PULLUP);  // Button input
  pinMode(SENSOR_PIN, INPUT_PULLUP);  // Sensor input
  
  // Configure OUTPUT pins
  // Assembly used: orr w0, w0, #(1<<21) for GPIO17 (output mode = 001)
  // Arduino: OUTPUT sets pin as output
  pinMode(LED_PIN, OUTPUT);           // LED output
  pinMode(BUZZER_PIN, OUTPUT);        // Buzzer output
  
  // Initialize outputs to OFF state
  // Assembly used: str to GPCLR0 register to clear pins
  digitalWrite(LED_PIN, LOW);
  digitalWrite(BUZZER_PIN, LOW);
  
  // Optional: Serial for debugging
  Serial.begin(9600);
  Serial.println("Alarm System Ready!");
  Serial.println("Waiting for button press or sensor trigger...");
}

// ============ MAIN LOOP ============
// Equivalent to the 'loop:' label in assembly
void loop() {
  // Read both inputs (Active LOW logic)
  // Assembly: ldr w0, [x19, #GPLEV0] then tst w0, #(1<<23)
  // Arduino: digitalRead returns HIGH or LOW
  bool buttonPressed = (digitalRead(BUTTON_PIN) == LOW);
  bool sensorTriggered = (digitalRead(SENSOR_PIN) == LOW);
  
  // Check if either input is triggered
  // Assembly: b.eq trigger (branch if zero flag set, meaning LOW)
  if (buttonPressed || sensorTriggered) {
    if (buttonPressed) {
      Serial.println("BUTTON PRESSED - Triggering alarm!");
    } else {
      Serial.println("SENSOR TRIGGERED - Triggering alarm!");
    }
    triggerAlarm();
  }
}

// ============ ALARM FUNCTION ============
// Equivalent to 'trigger:' and 'alarm_cycle:' labels in assembly
void triggerAlarm() {
  // Run alarm for specified number of cycles
  // Assembly: mov x20, #5 (alarm cycles counter)
  for (int cycle = 0; cycle < ALARM_CYCLES; cycle++) {
    Serial.print("Alarm cycle: ");
    Serial.print(cycle + 1);
    Serial.print(" of ");
    Serial.println(ALARM_CYCLES);
    
    // 1. Turn LED ON (Solid)
    // Assembly: mov w0, #(1<<17) then str w0, [x19, #GPSET0]
    digitalWrite(LED_PIN, HIGH);
    
    // 2. Buzzer PWM Loop (approx 0.5s total)
    // Assembly: mov x21, #50 (pwm loop counter)
    // Using software PWM for volume control (10% duty cycle)
    // 10% duty cycle means buzzer is ON only 10% of the time = quieter
    for (int i = 0; i < PWM_ITERATIONS; i++) {
      // Buzzer ON for 1ms
      // Assembly: mov w0, #(1<<22) then str w0, [x19, #GPSET0]
      digitalWrite(BUZZER_PIN, HIGH);
      delayMicroseconds(PWM_ON_TIME_US);
      
      // Buzzer OFF for 9ms
      // Assembly: mov w0, #(1<<22) then str w0, [x19, #GPCLR0]
      digitalWrite(BUZZER_PIN, LOW);
      delayMicroseconds(PWM_OFF_TIME_US);
    }
    
    // 3. Turn LED OFF
    // Assembly: mov w0, #(1<<17) then str w0, [x19, #GPCLR0]
    digitalWrite(LED_PIN, LOW);
    
    // 4. Silence delay (0.5s)
    // Assembly: ldr x0, =ts_500ms then bl do_sleep
    delay(SILENCE_DELAY_MS);
  }
  
  Serial.println("Alarm complete - returning to monitoring...");
  Serial.println();
}
