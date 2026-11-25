# تقرير التصميم الهندسي لشريحة PCF8574 / PCF8574A بلغة VHDL
## Complete Hardware Design & Verification Report

---

## 1. المقدمة ونظرة عامة (Introduction & Overview)

شريحة **PCF8574** (وشقيقتها **PCF8574A**) من إنتاج شركة NXP Semiconductors (سابقاً Philips) هي دائرة متكاملة رائدة تعمل كموسع منافذ رقمية ذات 8 بتات (**Remote 8-bit I/O Expander**) يتم التحكم بها تسلسلياً عبر ناقل **$I^2C$** بسرعات تصل إلى 100 kHz (Standard Mode) و 400 kHz (Fast Mode).

تتميز الشريحة بالمواصفات الهندسية التالية:
* **منافذ شبه ثنائية الاتجاه (Quasi-Bidirectional I/Os):** 8 منافذ ($P0$ إلى $P7$) يمكن استخدامها كمداخل أو مخارج مباشرة دون الحاجة لمسجل تحديد الاتجاه (Data Direction Register - DDR).
* **مخرج مقاطعة ذكي ($\overline{\text{INT}}$):** مخرج مجمع مفتوح (Open-Drain) ينبه المعالج الدقيق تلقائياً عند حدوث أي تغير في حالة المنافذ المهيأة كمدخلات، مما يرفع كفاءة المعالج ويلغي الحاجة للمسح الدوري المستمر (Polling).
* **عنونة مرنة عبر العتاد (Hardware Address Pins):** ثلاثة أطراف ($A0, A1, A2$) تتيح توصيل حتى 8 شرائح على نفس خط الـ $I^2C$.
* **الفرق بين النسختين:**
  * **PCF8574:** البادئة الثابتة للعنوان هي `0100` (مجال العناوين من `0x20` إلى `0x27`).
  * **PCF8574A:** البادئة الثابتة للعنوان هي `0111` (مجال العناوين من `0x38` إلى `0x3F`).
  * يتيح ذلك ربط حتى 16 شريحة على نفس الناقل (8 من كل نوع)، وتوفير حتى 128 منفذ I/O.

---

## 2. المخطط المعماري للشريحة (Block Diagram)

```
                       +---------------------------------------------------+
                       |                   PCF8574 / A                     |
                       |                                                   |
      SCL ------------>| [Glitch Filter] ---> SCL Edge / Clock Detect      |
      SDA <----------->| [Glitch Filter] ---> START / STOP Condition       |
                       |                      Shift Register & I2C FSM     |
                       |                                 |                 |
  A0, A1, A2 --------->| [Address Matcher] <-------------+                 |
                       |   (0100 or 0111)                |                 |
                       |                                 v                 |
                       |                      +-----------------------+    |
                       |                      | Port Register (8-Bit) |    |
                       |                      +-----------------------+    |
                       |                                 |                 |
                       |                                 v                 |
  P0 - P7  <---------->| <--- [Quasi-Bidirectional Open-Drain Drivers] <---+
                       |                      |          |                 |
                       |                      v          |                 |
                       |             [Change Detector]   |                 |
                       |                      |          |                 |
                       |                      v          |                 |
  INT_N    <-----------| <--- [Active-Low Open-Drain INT Latch] -----------+
                       |                                                   |
      VDD / VSS        | Power-On Reset (POR): Initializes to 0xFF         |
                       +---------------------------------------------------+
```

---

## 3. التحليل الهندسي لوظائف الشريحة (Detailed Functional Analysis)

### أ. المنافذ شبه ثنائية الاتجاه (Quasi-Bidirectional I/Os)
تعتمد الشريحة على هيكل ذكي للأطراف:
1. **كتابة منطق '0' (Output LOW):**
   * يتم تفعيل ترانزستور NMOS داخلي قوي متصل بالأرضي (GND)، مما يجبر الطرف على الانخفاض إلى المستوى المنخفض '0' وسحب التيار (Current Sinking).
2. **كتابة منطق '1' (Input Mode / High-Z):**
   * يتم إيقاف ترانزستور الـ NMOS، ويبقى الطرف معتمداً على مقاومة الرفع الضعيفة (Weak Internal Pull-up).
   * في هذه الحالة، يمكن لأي جهاز أو مفتاح خارجي سحب الطرف إلى '0' بأمان دون قصر كهربائي.
   * قراءة المنفذ في هذه اللحظة تقرأ الجهد الفعلي على الطرف الخارجي.
3. **الحالة الافتراضية عند التشغيل (POR):**
   * عند إقلاع التغذية (Power-On Reset)، يتم ضبط جميع البتات في مسجل المنفذ على '1' (`0xFF`) تلقائياً، بحيث تكون جميع الأطراف جاهزة كمدخلات آمنة مباشرة.

### ب. منطق توليد وتصفير المقاطعة ($\overline{\text{INT}}$)
1. **مخرج المقاطعة:** مجمع مفتوح (Open-Drain)، نشط على المستوى المنخفض ($\text{Active-LOW}$). يتطلب مقاومة رفع خارجية ($4.7\text{k}\Omega - 10\text{k}\Omega$) إلى $V_{DD}$.
2. **شروط إطلاق المقاطعة:**
   * يتم رصد أي تغير (حافة صاعدة أو هابطة) على أي طرف مهيأ كمدخل (أي أن البت المقابل له في مسجل المنفذ يساوي '1').
   * عند حدوث التغير، ينخفض خط $\overline{\text{INT}}$ إلى '0'.
3. **الشروط الدقيقة لإلغاء المقاطعة وفقاً للـ Datasheet:**
   * **الحالة 1 (Pin Reversion):** إذا عاد الطرف الخارجي لحالته السابقة الأصلية قبل أن يقرأه المعالج، تعود المقاطعة إلى '1' (تلتغى ذاتياً).
   * **الحالة 2 (Read Cycle):** عند قراءة المعالج لمنفذ الإدخال، يتم تصفير المقاطعة وإعادتها إلى '1' عند نبضة التأكيد (ACK bit) بعد الحافة الصاعدة لـ SCL.
   * **الحالة 3 (Write Cycle):** عند كتابة المعالج لبيانات جديدة للمنفذ، يتم تصفير المقاطعة عند نبضة التأكيد (ACK bit) بعد الحافة الهابطة لـ SCL.

---

## 4. مخطط آلة الحالة التتابعية لـ I2C (I2C FSM State Machine)

```mermaid
stateDiagram-v2
    [*] --> ST_IDLE
    ST_IDLE --> ST_ADDR : START Condition Detected
    ST_ADDR --> ST_ADDR_ACK : 8 Bits Received & Address Matches
    ST_ADDR --> ST_WAIT_STOP : Address Mismatch
    
    ST_ADDR_ACK --> ST_WRITE_DATA : R/W = '0' (Write Mode)
    ST_ADDR_ACK --> ST_READ_DATA : R/W = '1' (Read Mode)
    
    ST_WRITE_DATA --> ST_WRITE_ACK : 8 Bits Data Received
    ST_WRITE_ACK --> ST_WRITE_DATA : SCL Falling (Update Port & Clear INT)
    
    ST_READ_DATA --> ST_READ_ACK : 8 Bits Data Transmitted
    ST_READ_ACK --> ST_READ_DATA : Master sends ACK (Wants Next Byte)
    ST_READ_ACK --> ST_WAIT_STOP : Master sends NACK (End of Read)
    
    ST_WAIT_STOP --> ST_IDLE : STOP Condition Detected
    ST_WAIT_STOP --> ST_ADDR : Repeated START Detected
```

---

## 5. هيكلية ملفات المشروع (Project Structure)

| الملف | المسار | الوظيفة |
| :--- | :--- | :--- |
| `pcf8574_pkg.vhd` | `rtl/` | حزمة VHDL تحتوي على تعريفات الثوابت، عناوين PCF8574/A، وأنماط آلة الحالة |
| `i2c_filter.vhd` | `rtl/` | مرشح رقمي ومزامن (Glitch Filter) لقمع النبضات العابرة والضوضاء (< 50ns) ومعالجة إشارات 'H'/'L' |
| `pcf8574_core.vhd` | `rtl/` | النواة الرقمية: بروتوكول I2C، فك تشفير العنوان، مسجل المنافذ، كاشف المقاطعة |
| `pcf8574.vhd` | `rtl/` | الكيان العلوي (Top-Level) المطابق لأطراف الشريحة الحقيقية مع مشغلات Open-Drain |
| `pcf8574_tb.vhd` | `tb/` | منصة اختبار ذاتية التحقق (Self-Checking Testbench) تضم 10 سيناريوهات شاملة |
| `run_sim.bat` | `sim/` | سكربت دفعي لنظام Windows لبناء المشروع وتشغيل المحاكاة واستخراج ملف الموجات VCD |
| `run_sim.ps1` | `sim/` | سكربت PowerShell للتشغيل التلقائي والمحاكاة عبر GHDL |

---

## 6. نتائج التحقق والمحاكاة (Verification Results)

تم تنفيذ منصة اختبار ذاتية التحقق تحتوي على 10 اختبارات شاملة، وجاءت جميع النتائج ناجحة بنسبة 100%:

```
==========================================================
   STARTING PCF8574 / PCF8574A COMPREHENSIVE TESTBENCH   
==========================================================
TEST 1: Checking Power-on Reset Defaults...
TEST 1: PASSED (All ports 0xFF, INT_N = '1').

TEST 2: Testing Address Rejection (sending non-existent address 0x27)...
TEST 2: PASSED (Non-matching address ignored).

TEST 3: Testing I2C Write byte 0xAA to PCF8574 (Address 0x20)...
TEST 3: PASSED (Port correctly updated to 0xAA).

TEST 4: Testing Quasi-Bidirectional behavior...
Read back value from port: 208 (0xD0)
TEST 4: PASSED (Quasi-bidirectional input reading verified).

TEST 5: Testing Interrupt Generation upon external input change...
Applying falling edge to Pin 3 (button press)...
TEST 5: PASSED (INT_N correctly asserted LOW).

TEST 6: Testing Interrupt Clearing during I2C Read...
TEST 6: PASSED (INT_N correctly cleared on Read).

TEST 7: Testing Interrupt Clearing on Pin Reversion...
TEST 7: PASSED (INT_N deasserted on reversion).

TEST 8: Testing Interrupt Clearing on I2C Write...
TEST 8: PASSED (INT_N cleared on Write).

TEST 9: Testing PCF8574A variant (Address 0x39)...
TEST 9: PASSED (PCF8574A variant responded correctly).

TEST 10: Testing Repeated START condition...
TEST 10: PASSED (Repeated START handled seamlessly).

==========================================================
   ALL 10 VERIFICATION TESTS COMPLETED SUCCESSFULLY!      
==========================================================
```

تم حفظ ملف الموجات التوقيتية الكامل في: `sim/pcf8574_tb.vcd` (بحجم ~3.9 ميجابايت).

---

## 7. دليل التركيب والتصنيع على FPGAs / ASICs

التصميم مكتوب بأسلوب متزامن وصالح للتركيب العتادي بنسبة 100% (**100% Fully Synthesizable VHDL**)، ومتوافق مع جميع بيئات التطوير الشهيرة:
* **AMD / Xilinx Vivado & ISE**
* **Intel / Altera Quartus Prime**
* **Lattice Diamond / Radiant**
* **Microchip Libero SoC**
* **GHDL / ModelSim / QuestaSim / Riviera-PRO**
