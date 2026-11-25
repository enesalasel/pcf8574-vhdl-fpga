// =============================================================================
// Clean 1602 Character LCD Demo via FPGA-Implemented PCF8574 (Tang Nano 20K)
// =============================================================================

#include <Wire.h>
#include <LiquidCrystal_I2C.h>

LiquidCrystal_I2C lcd(0x20, 16, 2);

void setup() {
  Serial.begin(115200);
  delay(100);

  Wire.begin();
  Wire.setClock(100000);
  pinMode(A4, INPUT); // Disable Uno internal 5V pull-ups for 3.3V FPGA safety
  pinMode(A5, INPUT);

  Wire.beginTransmission(0x20);
  if (Wire.endTransmission() == 0) {
    Serial.println(F("[OK] FPGA PCF8574 detected at 0x20"));
  } else {
    Serial.println(F("[ERR] FPGA PCF8574 not responding at 0x20"));
  }

  lcd.init();
  lcd.backlight();
  lcd.clear();

  lcd.setCursor(0, 0);
  lcd.print(F("Tang Nano 20K"));
  lcd.setCursor(0, 1);
  lcd.print(F("PCF8574 Ready "));
}

unsigned long count = 0;
void loop() {
  delay(1000);
  count++;
  lcd.setCursor(13, 1);
  lcd.print(count % 100);
  lcd.print(F(" "));
}
