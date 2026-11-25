--------------------------------------------------------------------------------
-- Project: PCF8574 / PCF8574A Remote 8-Bit I/O Expander for I2C-Bus
-- File   : pcf8574_tb.vhd
-- Description: Comprehensive self-checking testbench verifying:
--              1. Power-on reset defaults
--              2. I2C address matching and rejection
--              3. I2C Write operation to quasi-bidirectional ports
--              4. Quasi-bidirectional behavior with external loads
--              5. I2C Read operation of physical pin voltages
--              6. Interrupt generation on input pin change
--              7. Interrupt clearing upon I2C Read ACK
--              8. Interrupt clearing upon input pin reversion
--              9. Interrupt clearing upon I2C Write ACK
--              10. PCF8574A address variant (0111xxx)
--              11. Repeated START condition handling
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pcf8574_pkg.all;

entity pcf8574_tb is
end entity pcf8574_tb;

architecture sim of pcf8574_tb is

    -- System Clock and Reset
    constant CLK_PERIOD : time := 50 ns; -- 20 MHz system clock
    constant I2C_HALF_PERIOD : time := 1250 ns; -- 400 kHz I2C Fast-mode (half period)

    signal clk   : std_logic := '0';
    signal rst_n : std_logic := '0';

    -- Address pins for PCF8574 (Standard)
    signal a0 : std_logic := '0';
    signal a1 : std_logic := '0';
    signal a2 : std_logic := '0';

    -- Address pins for PCF8574A (Variant)
    signal a0_a : std_logic := '1';
    signal a1_a : std_logic := '0';
    signal a2_a : std_logic := '0';

    -- I2C Bus signals
    signal scl          : std_logic := 'Z';
    signal sda          : std_logic := 'Z';
    signal sda_master   : std_logic := 'Z';
    signal scl_master   : std_logic := 'Z';

    -- PCF8574 (Standard) Port and Interrupt
    signal p            : std_logic_vector(7 downto 0) := (others => 'Z');
    signal p_ext_drive  : std_logic_vector(7 downto 0) := (others => 'Z');
    signal int_n        : std_logic := 'Z';

    -- PCF8574A (Variant) Port and Interrupt
    signal p_a           : std_logic_vector(7 downto 0) := (others => 'Z');
    signal p_a_ext_drive : std_logic_vector(7 downto 0) := (others => 'Z');
    signal int_n_a       : std_logic := 'Z';

    -- Test status flags
    signal tests_passed : boolean := true;
    signal sim_done     : boolean := false;

begin

    ----------------------------------------------------------------------------
    -- Clock Generation (20 MHz)
    ----------------------------------------------------------------------------
    clk_gen: process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    ----------------------------------------------------------------------------
    -- Bus Pull-ups (Weak pull-up 'H' resolution)
    ----------------------------------------------------------------------------
    scl <= scl_master;
    sda <= sda_master;

    -- Pull-ups for I2C lines
    scl <= 'H';
    sda <= 'H';

    -- Pull-ups for Quasi-bidirectional ports and open-drain interrupts
    p     <= p_ext_drive;
    p_a   <= p_a_ext_drive;
    int_n <= 'H';
    int_n_a <= 'H';

    gen_pullup_p: for i in 0 to 7 generate
        p(i)   <= 'H';
        p_a(i) <= 'H';
    end generate;

    ----------------------------------------------------------------------------
    -- Device Under Test 1: PCF8574 (Address prefix "0100")
    ----------------------------------------------------------------------------
    dut_pcf8574 : pcf8574
        generic map (
            ADDR_PREFIX  => PCF8574_ADDR_PREFIX,
            FILTER_DEPTH => 3
        )
        port map (
            clk   => clk,
            rst_n => rst_n,
            a0    => a0,
            a1    => a1,
            a2    => a2,
            scl   => scl,
            sda   => sda,
            p     => p,
            int_n => int_n
        );

    ----------------------------------------------------------------------------
    -- Device Under Test 2: PCF8574A (Address prefix "0111")
    ----------------------------------------------------------------------------
    dut_pcf8574a : pcf8574
        generic map (
            ADDR_PREFIX  => PCF8574A_ADDR_PREFIX,
            FILTER_DEPTH => 3
        )
        port map (
            clk   => clk,
            rst_n => rst_n,
            a0    => a0_a,
            a1    => a1_a,
            a2    => a2_a,
            scl   => scl,
            sda   => sda,
            p     => p_a,
            int_n => int_n_a
        );

    ----------------------------------------------------------------------------
    -- Main Test Sequencer
    ----------------------------------------------------------------------------
    test_proc: process

        -- Helper procedure: I2C START Condition
        procedure i2c_start is
        begin
            sda_master <= 'Z';
            scl_master <= 'Z';
            wait for I2C_HALF_PERIOD;
            sda_master <= '0';
            wait for I2C_HALF_PERIOD;
            scl_master <= '0';
            wait for I2C_HALF_PERIOD;
        end procedure;

        -- Helper procedure: I2C STOP Condition
        procedure i2c_stop is
        begin
            sda_master <= '0';
            wait for I2C_HALF_PERIOD;
            scl_master <= 'Z';
            wait for I2C_HALF_PERIOD;
            sda_master <= 'Z';
            wait for I2C_HALF_PERIOD;
        end procedure;

        -- Helper procedure: I2C Repeated START Condition
        procedure i2c_repeated_start is
        begin
            sda_master <= 'Z';
            wait for I2C_HALF_PERIOD;
            scl_master <= 'Z';
            wait for I2C_HALF_PERIOD;
            sda_master <= '0';
            wait for I2C_HALF_PERIOD;
            scl_master <= '0';
            wait for I2C_HALF_PERIOD;
        end procedure;

        -- Helper procedure: I2C Write Byte and sample ACK/NACK
        procedure i2c_write_byte(
            constant data_byte : in  std_logic_vector(7 downto 0);
            variable ack_bit   : out std_logic
        ) is
        begin
            for i in 7 downto 0 loop
                -- 1. Setup SDA while SCL is LOW
                if data_byte(i) = '0' then
                    sda_master <= '0';
                else
                    sda_master <= 'Z';
                end if;
                wait for I2C_HALF_PERIOD;

                -- 2. Pulse SCL HIGH
                scl_master <= 'Z';
                wait for I2C_HALF_PERIOD;

                -- 3. Bring SCL LOW
                scl_master <= '0';
                wait for I2C_HALF_PERIOD / 2;
            end loop;

            -- 9th clock: Slave ACK
            sda_master <= 'Z'; -- Release SDA for slave
            wait for I2C_HALF_PERIOD / 2;
            scl_master <= 'Z';
            wait for I2C_HALF_PERIOD / 2;
            if to_X01(sda) = '0' then
                ack_bit := '0';
            else
                ack_bit := '1';
            end if;
            wait for I2C_HALF_PERIOD / 2;
            scl_master <= '0';
            wait for I2C_HALF_PERIOD;
        end procedure;

        -- Helper procedure: I2C Read Byte and send Master ACK/NACK
        procedure i2c_read_byte(
            variable data_byte : out std_logic_vector(7 downto 0);
            constant send_ack  : in  boolean
        ) is
            variable sampled_bit : std_logic;
        begin
            sda_master <= 'Z'; -- Slave drives SDA
            for i in 7 downto 0 loop
                wait for I2C_HALF_PERIOD;
                scl_master <= 'Z';
                wait for I2C_HALF_PERIOD / 2;
                if to_X01(sda) = '0' then
                    sampled_bit := '0';
                else
                    sampled_bit := '1';
                end if;
                data_byte(i) := sampled_bit;
                wait for I2C_HALF_PERIOD / 2;
                scl_master <= '0';
            end loop;

            -- 9th clock: Master sends ACK/NACK
            wait for I2C_HALF_PERIOD / 2;
            if send_ack then
                sda_master <= '0'; -- ACK
            else
                sda_master <= 'Z'; -- NACK
            end if;
            wait for I2C_HALF_PERIOD / 2;
            scl_master <= 'Z';
            wait for I2C_HALF_PERIOD;
            scl_master <= '0';
            sda_master <= 'Z';
            wait for I2C_HALF_PERIOD;
        end procedure;

        variable ack_resp : std_logic;
        variable read_val : std_logic_vector(7 downto 0);

    begin
        report "==========================================================";
        report "   STARTING PCF8574 / PCF8574A COMPREHENSIVE TESTBENCH   ";
        report "==========================================================";

        -- Assert Reset
        rst_n <= '0';
        wait for 200 ns;
        rst_n <= '1';
        wait for 200 ns;

        ------------------------------------------------------------------------
        -- TEST 1: Check Power-On Reset Defaults
        ------------------------------------------------------------------------
        report "TEST 1: Checking Power-on Reset Defaults...";
        assert to_X01(int_n) = '1'
            report "FAIL: int_n should default to inactive ('1') after reset!"
            severity failure;
        for i in 0 to 7 loop
            assert to_X01(p(i)) = '1'
                report "FAIL: Port pin " & integer'image(i) & " should default to '1' ('H')!"
                severity failure;
        end loop;
        report "TEST 1: PASSED (All ports 0xFF, INT_N = '1').";

        ------------------------------------------------------------------------
        -- TEST 2: Address Rejection
        ------------------------------------------------------------------------
        report "TEST 2: Testing Address Rejection (sending non-existent address 0x27)...";
        i2c_start;
        -- Address 0x27 + Write (7'b0100111 & 1'b0 = 0x4E)
        i2c_write_byte("01001110", ack_resp);
        assert ack_resp = '1'
            report "FAIL: Device should NOT ACK non-matching address 0x27!"
            severity failure;
        i2c_stop;
        report "TEST 2: PASSED (Non-matching address ignored).";

        ------------------------------------------------------------------------
        -- TEST 3: I2C Write to PCF8574 (Port Address 0x20: 0100_000_0)
        ------------------------------------------------------------------------
        report "TEST 3: Testing I2C Write byte 0xAA to PCF8574 (Address 0x20)...";
        i2c_start;
        -- Address 0x20 + Write (7'b0100000 & 1'b0 = 0x40)
        i2c_write_byte("01000000", ack_resp);
        assert ack_resp = '0'
            report "FAIL: PCF8574 did NOT ACK address 0x20!"
            severity failure;

        -- Write data 0xAA (10101010)
        i2c_write_byte("10101010", ack_resp);
        assert ack_resp = '0'
            report "FAIL: PCF8574 did NOT ACK data byte 0xAA!"
            severity failure;
        i2c_stop;

        wait for 200 ns;
        -- Verify output pins: bits 7,5,3,1 are '1', bits 6,4,2,0 are '0'
        for i in 0 to 7 loop
            if i rem 2 = 0 then
                assert to_X01(p(i)) = '0'
                    report "FAIL: Port pin " & integer'image(i) & " should be driven LOW ('0')!"
                    severity failure;
            else
                assert to_X01(p(i)) = '1'
                    report "FAIL: Port pin " & integer'image(i) & " should be HIGH ('1')!"
                    severity failure;
            end if;
        end loop;
        report "TEST 3: PASSED (Port correctly updated to 0xAA).";

        ------------------------------------------------------------------------
        -- TEST 4: Quasi-Bidirectional Behavior (External Pulldown on Pin)
        ------------------------------------------------------------------------
        report "TEST 4: Testing Quasi-Bidirectional behavior...";
        -- Write 0xF0 (pins 7..4 = '1' / input mode; pins 3..0 = '0' / driven low)
        i2c_start;
        i2c_write_byte("01000000", ack_resp);
        i2c_write_byte("11110000", ack_resp);
        i2c_stop;
        wait for 200 ns;

        -- Pull external pin 5 LOW
        p_ext_drive(5) <= '0';
        wait for 500 ns;
        assert to_X01(p(5)) = '0'
            report "FAIL: Pin 5 should be pulled LOW by external source!"
            severity failure;

        -- Read back through I2C: Address 0x20 + Read (7'b0100000 & 1'b1 = 0x41)
        i2c_start;
        i2c_write_byte("01000001", ack_resp);
        assert ack_resp = '0'
            report "FAIL: PCF8574 did NOT ACK read address 0x20!"
            severity failure;

        i2c_read_byte(read_val, false); -- send NACK to end read
        i2c_stop;

        -- Expect: 11010000 (0xD0) because bit 5 was pulled low externally
        report "Read back value from port: " & integer'image(to_integer(unsigned(read_val)));
        assert read_val = "11010000"
            report "FAIL: Expected read value 0xD0 (11010000), got: " &
                   integer'image(to_integer(unsigned(read_val)))
            severity failure;

        p_ext_drive(5) <= 'Z'; -- Release external drive
        wait for 200 ns;
        report "TEST 4: PASSED (Quasi-bidirectional input reading verified).";

        ------------------------------------------------------------------------
        -- TEST 5 & 6: Interrupt Generation and Clearing on Read
        ------------------------------------------------------------------------
        report "TEST 5: Testing Interrupt Generation upon external input change...";
        -- Reset port to all '1's
        i2c_start;
        i2c_write_byte("01000000", ack_resp);
        i2c_write_byte("11111111", ack_resp);
        i2c_stop;
        wait for 500 ns;

        assert to_X01(int_n) = '1'
            report "FAIL: int_n should be HIGH before external trigger!"
            severity failure;

        -- External trigger: pull Pin 3 LOW
        report "Applying falling edge to Pin 3 (button press)...";
        p_ext_drive(3) <= '0';
        wait for 500 ns; -- Wait for filter depth

        assert to_X01(int_n) = '0'
            report "FAIL: int_n did NOT assert LOW after Pin 3 state change!"
            severity failure;
        report "TEST 5: PASSED (INT_N correctly asserted LOW).";

        report "TEST 6: Testing Interrupt Clearing during I2C Read...";
        i2c_start;
        i2c_write_byte("01000001", ack_resp);
        i2c_read_byte(read_val, false); -- NACK
        i2c_stop;

        wait for 200 ns;
        -- Now interrupt should be cleared
        assert to_X01(int_n) = '1'
            report "FAIL: int_n was NOT cleared after I2C Read!"
            severity failure;
        report "TEST 6: PASSED (INT_N correctly cleared on Read).";

        -- Release pin 3
        p_ext_drive(3) <= 'Z';
        wait for 500 ns;
        -- Releasing pin 3 is another state change (rising edge), so INT_N should assert again!
        assert to_X01(int_n) = '0'
            report "FAIL: int_n did NOT assert LOW after Pin 3 rising edge release!"
            severity failure;

        ------------------------------------------------------------------------
        -- TEST 7: Interrupt Clearing on Pin Reversion
        ------------------------------------------------------------------------
        report "TEST 7: Testing Interrupt Clearing on Pin Reversion...";
        -- Push pin 3 back to '0' (reverting to baseline)
        p_ext_drive(3) <= '0';
        wait for 500 ns;
        assert to_X01(int_n) = '1'
            report "FAIL: int_n should deassert when input reverts to baseline!"
            severity failure;
        report "TEST 7: PASSED (INT_N deasserted on reversion).";

        -- Clear baseline via read
        i2c_start;
        i2c_write_byte("01000001", ack_resp);
        i2c_read_byte(read_val, false);
        i2c_stop;
        p_ext_drive(3) <= 'Z';
        wait for 500 ns;
        -- Read to clear
        i2c_start;
        i2c_write_byte("01000001", ack_resp);
        i2c_read_byte(read_val, false);
        i2c_stop;
        wait for 200 ns;

        ------------------------------------------------------------------------
        -- TEST 8: Interrupt Clearing on Write
        ------------------------------------------------------------------------
        report "TEST 8: Testing Interrupt Clearing on I2C Write...";
        p_ext_drive(1) <= '0';
        wait for 500 ns;
        assert to_X01(int_n) = '0'
            report "FAIL: int_n should be LOW after Pin 1 change!"
            severity failure;

        -- Write to port
        i2c_start;
        i2c_write_byte("01000000", ack_resp);
        i2c_write_byte("11111101", ack_resp); -- write 0 to pin 1
        i2c_stop;
        wait for 200 ns;

        assert to_X01(int_n) = '1'
            report "FAIL: int_n did NOT clear after I2C Write!"
            severity failure;
        p_ext_drive(1) <= 'Z';
        report "TEST 8: PASSED (INT_N cleared on Write).";

        ------------------------------------------------------------------------
        -- TEST 9: PCF8574A Variant Address Test (0111_A2_A1_A0 = 0x39 for A=001)
        ------------------------------------------------------------------------
        report "TEST 9: Testing PCF8574A variant (Address 0x39)...";
        i2c_start;
        -- 7'b0111001 & 1'b0 = 0x72
        i2c_write_byte("01110010", ack_resp);
        assert ack_resp = '0'
            report "FAIL: PCF8574A did NOT ACK address 0x39!"
            severity failure;

        i2c_write_byte("01010101", ack_resp); -- 0x55
        assert ack_resp = '0'
            report "FAIL: PCF8574A did NOT ACK data byte!"
            severity failure;
        i2c_stop;

        wait for 200 ns;
        for i in 0 to 7 loop
            if i rem 2 = 1 then
                assert to_X01(p_a(i)) = '0'
                    report "FAIL: PCF8574A pin " & integer'image(i) & " mismatch!"
                    severity failure;
            else
                assert to_X01(p_a(i)) = '1'
                    report "FAIL: PCF8574A pin " & integer'image(i) & " mismatch!"
                    severity failure;
            end if;
        end loop;
        report "TEST 9: PASSED (PCF8574A variant responded correctly).";

        ------------------------------------------------------------------------
        -- TEST 10: Repeated START Condition
        ------------------------------------------------------------------------
        report "TEST 10: Testing Repeated START condition...";
        i2c_start;
        i2c_write_byte("01000000", ack_resp);
        i2c_write_byte("11110000", ack_resp);
        -- Repeated START without STOP
        i2c_repeated_start;
        i2c_write_byte("01000001", ack_resp);
        assert ack_resp = '0'
            report "FAIL: Slave did NOT ACK after Repeated START!"
            severity failure;
        i2c_read_byte(read_val, false);
        i2c_stop;

        assert read_val = "11110000"
            report "FAIL: Repeated START read value mismatch!"
            severity failure;
        report "TEST 10: PASSED (Repeated START handled seamlessly).";

        ------------------------------------------------------------------------
        -- All Tests Completed
        ------------------------------------------------------------------------
        report "==========================================================";
        report "   ALL 10 VERIFICATION TESTS COMPLETED SUCCESSFULLY!      ";
        report "==========================================================";

        wait for 1 us;
        sim_done <= true;
        wait;
    end process;

end architecture sim;
