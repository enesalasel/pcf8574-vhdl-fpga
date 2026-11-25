--------------------------------------------------------------------------------
-- Project: PCF8574 / PCF8574A Remote 8-Bit I/O Expander for I2C-Bus
-- File   : pcf8574_tang20k_top.vhd
-- Target : Sipeed Tang Nano 20K (Gowin GW2AR-LV18QN88C8/I7)
-- Description: Board-specific top-level wrapper around the pure pcf8574 IP.
--              Provides automatic internal Power-On Reset (POR), NXP-style
--              0->1 transient rise-time boost, and 6 onboard diagnostic LEDs.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pcf8574_pkg.all;

entity pcf8574_tang20k_top is
    port (
        -- 27 MHz Onboard Crystal Oscillator (Pin 4)
        clk   : in    std_logic;

        -- Hardware Address Pins (A0, A1, A2)
        a0    : in    std_logic;
        a1    : in    std_logic;
        a2    : in    std_logic;

        -- I2C Serial Bus
        scl   : in    std_logic;
        sda   : inout std_logic;

        -- 8 Quasi-Bidirectional I/O Pins (P0 - P7)
        p     : inout std_logic_vector(7 downto 0);

        -- Open-Drain Active-Low Interrupt Output
        int_n : out   std_logic;

        -- 6 Onboard Diagnostic LEDs (Active-Low: '0' = ON, '1' = OFF)
        led_n : out   std_logic_vector(5 downto 0)
    );
end entity pcf8574_tang20k_top;

architecture rtl of pcf8574_tang20k_top is

    -- Automatic internal Power-On Reset (~38 us at 27 MHz)
    signal por_cnt     : unsigned(9 downto 0) := (others => '0');
    signal rst_n_int   : std_logic := '0';
    signal int_n_sig   : std_logic;

    -- Onboard LED diagnostic pulse-stretchers
    signal hb_cnt      : unsigned(23 downto 0) := (others => '0');
    signal scl_stretch : unsigned(21 downto 0) := (others => '0');
    signal sda_stretch : unsigned(21 downto 0) := (others => '0');
    signal p2_stretch  : unsigned(21 downto 0) := (others => '0');
    signal int_stretch : unsigned(22 downto 0) := (others => '0');
    signal act_latched : std_logic := '0';

begin

    -- Internal Power-On Reset
    process(clk)
    begin
        if rising_edge(clk) then
            if por_cnt /= "1111111111" then
                por_cnt   <= por_cnt + 1;
                rst_n_int <= '0';
            else
                rst_n_int <= '1';
            end if;
        end if;
    end process;

    -- Instantiate Pure PCF8574 IP Core
    u_pcf8574 : pcf8574
        generic map (
            ADDR_PREFIX       => PCF8574_ADDR_PREFIX,
            FILTER_DEPTH      => 3,
            ENABLE_RISE_BOOST => true
        )
        port map (
            clk   => clk,
            rst_n => rst_n_int,
            a0    => a0,
            a1    => a1,
            a2    => a2,
            scl   => scl,
            sda   => sda,
            p     => p,
            int_n => int_n_sig
        );

    int_n <= int_n_sig;

    -- Onboard Diagnostic LEDs (Active-Low)
    --   LED0 (Pin 15): ~1.6 Hz heartbeat (confirms 27 MHz clock & active FPGA)
    --   LED1 (Pin 16): SCL bus activity
    --   LED2 (Pin 17): SDA bus activity
    --   LED3 (Pin 18): Interrupt (INT_N) active indicator
    --   LED4 (Pin 19): Latched I2C activity indicator
    --   LED5 (Pin 20): P[2] (LCD EN) strobe activity
    process(clk)
    begin
        if rising_edge(clk) then
            hb_cnt <= hb_cnt + 1;

            if scl = '0' then
                scl_stretch <= (others => '1');
                act_latched <= '1';
            elsif scl_stretch /= 0 then
                scl_stretch <= scl_stretch - 1;
            end if;

            if sda = '0' then
                sda_stretch <= (others => '1');
            elsif sda_stretch /= 0 then
                sda_stretch <= sda_stretch - 1;
            end if;

            if p(2) = '0' then
                p2_stretch <= (others => '1');
            elsif p2_stretch /= 0 then
                p2_stretch <= p2_stretch - 1;
            end if;

            if int_n_sig = '0' then
                int_stretch <= (others => '1');
            elsif int_stretch /= 0 then
                int_stretch <= int_stretch - 1;
            end if;
        end if;
    end process;

    led_n(0) <= hb_cnt(23);
    led_n(1) <= '0' when (scl_stretch /= 0) else '1';
    led_n(2) <= '0' when (sda_stretch /= 0) else '1';
    led_n(3) <= '0' when (int_stretch /= 0) else '1';
    led_n(4) <= '0' when (act_latched = '1') else '1';
    led_n(5) <= '0' when (p2_stretch /= 0) else '1';

end architecture rtl;
