--------------------------------------------------------------------------------
-- Project: PCF8574 / PCF8574A Remote 8-Bit I/O Expander for I2C-Bus
-- File   : pcf8574.vhd
-- Description: Pure, board-agnostic top-level IC entity matching the NXP
--              PCF8574 pinout with bidirectional inout ports, open-drain
--              drivers, optional 0->1 transient rise-time boost, and hardware
--              address selection.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pcf8574_pkg.all;

entity pcf8574 is
    generic (
        -- ADDR_PREFIX: "0100" for PCF8574 (0x20-0x27), "0111" for PCF8574A (0x38-0x3F)
        ADDR_PREFIX       : std_logic_vector(3 downto 0) := PCF8574_ADDR_PREFIX;
        -- Glitch filter depth for noise suppression (< 50ns)
        FILTER_DEPTH      : natural := 3;
        -- Optional NXP-style 0->1 transient strong-HIGH boost (~7 clk cycles)
        ENABLE_RISE_BOOST : boolean := false
    );
    port (
        -- Synchronous System Clock (typically 10 MHz to 50 MHz)
        clk          : in    std_logic;
        -- Active-Low Reset
        rst_n        : in    std_logic := '1';

        -- Hardware Address Pins (A0, A1, A2)
        a0           : in    std_logic;
        a1           : in    std_logic;
        a2           : in    std_logic;

        -- I2C Serial Bus
        scl          : in    std_logic;
        sda          : inout std_logic;

        -- 8 Quasi-Bidirectional I/O Pins (P0 - P7)
        p            : inout std_logic_vector(7 downto 0);

        -- Open-Drain Active-Low Interrupt Output
        int_n        : out   std_logic
    );
end entity pcf8574;

architecture rtl of pcf8574 is

    -- Reset Synchronizer (Asynchronous Assert, Synchronous Deassert)
    signal rst_sync1      : std_logic := '0';
    signal rst_sync2      : std_logic := '0';

    signal sda_drive_low  : std_logic;
    signal int_drive_low  : std_logic;
    signal port_drive_low : std_logic_vector(7 downto 0);

    signal a_vector       : std_logic_vector(2 downto 0);
    signal port_pin_in    : std_logic_vector(7 downto 0);

    -- Optional 0->1 transient rise-time boost counters
    type t_boost_arr is array (0 to 7) of unsigned(2 downto 0);
    signal port_drive_low_d : std_logic_vector(7 downto 0) := (others => '0');
    signal boost_cnt        : t_boost_arr := (others => (others => '0'));

begin

    a_vector    <= a2 & a1 & a0;
    port_pin_in <= p;

    ----------------------------------------------------------------------------
    -- Reset Synchronizer (Async Assert, Sync Deassert)
    ----------------------------------------------------------------------------
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            rst_sync1 <= '0';
            rst_sync2 <= '0';
        elsif rising_edge(clk) then
            rst_sync1 <= '1';
            rst_sync2 <= rst_sync1;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Instantiate PCF8574 Core Logic
    ----------------------------------------------------------------------------
    u_core : pcf8574_core
        generic map (
            ADDR_PREFIX  => ADDR_PREFIX,
            FILTER_DEPTH => FILTER_DEPTH
        )
        port map (
            clk            => clk,
            rst_n          => rst_sync2,
            a              => a_vector,
            scl_in         => scl,
            sda_in         => sda,
            sda_drive_low  => sda_drive_low,
            port_pin_in    => port_pin_in,
            port_drive_low => port_drive_low,
            int_drive_low  => int_drive_low
        );

    ----------------------------------------------------------------------------
    -- Open-Drain Drivers for SDA and INT_N
    ----------------------------------------------------------------------------
    sda   <= '0' when (sda_drive_low = '1') else 'Z';
    int_n <= '0' when (int_drive_low = '1') else 'Z';

    ----------------------------------------------------------------------------
    -- Quasi-Bidirectional Port Drivers (P0 - P7)
    ----------------------------------------------------------------------------
    gen_boost_en : if ENABLE_RISE_BOOST generate
        process(clk, rst_n)
        begin
            if rst_n = '0' then
                port_drive_low_d <= (others => '0');
                boost_cnt        <= (others => (others => '0'));
            elsif rising_edge(clk) then
                port_drive_low_d <= port_drive_low;
                for i in 0 to 7 loop
                    if port_drive_low(i) = '1' then
                        boost_cnt(i) <= (others => '0');
                    elsif port_drive_low_d(i) = '1' and port_drive_low(i) = '0' then
                        boost_cnt(i) <= (others => '1');
                    elsif boost_cnt(i) /= 0 then
                        boost_cnt(i) <= boost_cnt(i) - 1;
                    end if;
                end loop;
            end if;
        end process;

        gen_p_boost : for i in 0 to 7 generate
            p(i) <= '0' when (port_drive_low(i) = '1') else
                    '1' when (boost_cnt(i) /= 0) else
                    'Z';
        end generate;
    end generate;

    gen_boost_dis : if not ENABLE_RISE_BOOST generate
        gen_p_open_drain : for i in 0 to 7 generate
            p(i) <= '0' when (port_drive_low(i) = '1') else 'Z';
        end generate;
    end generate;

end architecture rtl;
