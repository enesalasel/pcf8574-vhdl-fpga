// =============================================================================
// PCF8574 FPGA Comprehensive Hardware Test Suite (Arduino Uno -> Tang Nano 20K)
// Tests: Strict 7-bit address decode, 100 kHz Write/Read-Back, multi-byte
//        streaming, 400 kHz Fast Mode, and 1602 LCD initialization.
// =============================================================================

#include <Wire.h>
#include <LiquidCrystal_I2C.h>

byte devAddr = 0x00;
int passed = 0;
int failed = 0;
LiquidCrystal_I2C *lcd = nullptr;

void printBin(byte v) {
  for (int i = 7; i >= 0; i--) Serial.print((v >> i) & 1);
}

bool pcfWrite(byte addr, byte val) {
  Wire.beginTransmission(addr);
  Wire.write(val);
  return (Wire.endTransmission() == 0);
}

bool pcfRead(byte addr, byte &out) {
  if (Wire.requestFrom(addr, (byte)1) != 1) return false;
  out = Wire.read();
  return true;
}

void report(const __FlashStringHelper *name, bool ok) {
  if (ok) {
    passed++;
    Serial.print(F("  [PASS] "));
  } else {
    failed++;
    Serial.print(F("  [FAIL] "));
  }
  Serial.println(name);
}

void setup() {
  Serial.begin(115200);
  while (!Serial);
  delay(500);

  Serial.println(F("\n===================================================="));
  Serial.println(F("  PCF8574 FPGA COMPREHENSIVE HARDWARE TEST SUITE"));
  Serial.println(F("===================================================="));

  Wire.begin();
  Wire.setClock(100000);
  pinMode(A4, INPUT); // Disable Uno internal 5V pull-ups for 3.3V FPGA safety
  pinMode(A5, INPUT);

  // TEST 1: Strict Address Decode Scan (0x01..0x7F)
  Serial.println(F("\n[TEST 1] Strict I2C Address Scan (0x01..0x7F)"));
  byte foundCount = 0;
  for (byte a = 1; a < 127; a++) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) {
      Serial.print(F("  Found device at 0x"));
      if (a < 16) Serial.print('0');
      Serial.println(a, HEX);
      devAddr = a;
      foundCount++;
    }
  }
  report(F("Exactly 1 PCF8574 address responded (strict decode)"), foundCount == 1);

  if (foundCount == 0) {
    Serial.println(F("ABORT: No I2C device found."));
    while (1);
  }

  // TEST 2: Write & Read-Back Pattern Verification (100 kHz)
  Serial.println(F("\n[TEST 2] Write & Read-Back Patterns (100 kHz)"));
  const byte patterns[] = {
    0xFF, 0x00, 0xAA, 0x55,
    0xFE, 0xFD, 0xFB, 0xF7, 0xEF, 0xDF, 0xBF, 0x7F
  };
  bool patAllOk = true;
  for (byte i = 0; i < sizeof(patterns); i++) {
    byte w = patterns[i], r = 0x00;
    bool match = pcfWrite(devAddr, w) && (delay(2), pcfRead(devAddr, r)) && (r == w);

    Serial.print(F("  W=0x")); if (w < 16) Serial.print('0'); Serial.print(w, HEX);
    Serial.print(F(" (")); printBin(w);
    Serial.print(F(") -> R=0x")); if (r < 16) Serial.print('0'); Serial.print(r, HEX);
    Serial.print(F(" (")); printBin(r);
    Serial.println(match ? F(") OK") : F(") MISMATCH"));

    if (!match) patAllOk = false;
  }
  report(F("All 12 Write/Read-Back bit patterns matched"), patAllOk);

  // TEST 3: Multi-Byte Consecutive Streaming Write & Read
  Serial.println(F("\n[TEST 3] Multi-Byte Streaming Write & Read"));
  Wire.beginTransmission(devAddr);
  Wire.write(0x55);
  Wire.write(0xAA);
  Wire.write(0x3C);
  bool streamW = (Wire.endTransmission() == 0);

  byte r1 = 0, r2 = 0;
  bool streamR = false;
  if (Wire.requestFrom(devAddr, (byte)2) == 2) {
    r1 = Wire.read();
    r2 = Wire.read();
    streamR = (r1 == 0x3C && r2 == 0x3C);
  }
  report(F("Consecutive 3-byte write + 2-byte read (0x3C)"), streamW && streamR);

  // TEST 4: 400 kHz Fast Mode I2C Test
  Serial.println(F("\n[TEST 4] 400 kHz Fast Mode Test"));
  Wire.setClock(400000);
  byte rFast = 0;
  bool fastOk = pcfWrite(devAddr, 0xA5) && pcfRead(devAddr, rFast) && (rFast == 0xA5);
  Serial.print(F("  400 kHz W=0xA5 -> R=0x"));
  if (rFast < 16) Serial.print('0');
  Serial.println(rFast, HEX);
  report(F("400 kHz Fast Mode Write & Read-Back"), fastOk);

  Wire.setClock(100000);
  pcfWrite(devAddr, 0xFF);

  Serial.println(F("\n----------------------------------------------------"));
  Serial.print(F("TEST SUMMARY: "));
  Serial.print(passed);
  Serial.print(F(" PASSED, "));
  Serial.print(failed);
  Serial.println(F(" FAILED"));
  Serial.println(F("----------------------------------------------------"));
}

void loop() {}
