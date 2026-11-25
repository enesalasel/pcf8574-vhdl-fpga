--------------------------------------------------------------------------------
-- Project: PCF8574 / PCF8574A Remote 8-Bit I/O Expander for I2C-Bus
-- File   : i2c_filter.vhd
-- Description: Dedicated 2-FF metastability synchronizer followed by a digital
--              glitch filter for asynchronous bus inputs (SCL, SDA, P0-P7).
--              Suppresses high-frequency noise and spikes (< 50ns per I2C spec).
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_filter is
    generic (
        FILTER_DEPTH : natural := 3
    );
    port (
        clk     : in  std_logic;
        rst_n   : in  std_logic;
        sig_in  : in  std_logic;
        sig_out : out std_logic
    );
end entity i2c_filter;

architecture rtl of i2c_filter is
    -- Dedicated 2-stage CDC synchronizer (isolates metastability from filter logic)
    signal sync_ff1  : std_logic := '1';
    signal sync_ff2  : std_logic := '1';

    -- Glitch filter shift register (operates strictly on synchronized sync_ff2)
    signal shift_reg : std_logic_vector(FILTER_DEPTH - 1 downto 0) := (others => '1');
    signal out_reg   : std_logic := '1';
    signal sig_norm  : std_logic;

    attribute syn_preserve : boolean;
    attribute syn_preserve of sync_ff1 : signal is true;
    attribute syn_preserve of sync_ff2 : signal is true;
begin

    -- Normalize IEEE 1164 resolved bus states ('H' -> '1', 'L' -> '0') for simulation
    sig_norm <= '1' when (to_X01(sig_in) = '1') else '0';

    process(clk, rst_n)
        constant ALL_ONES  : std_logic_vector(FILTER_DEPTH - 1 downto 0) := (others => '1');
        constant ALL_ZEROS : std_logic_vector(FILTER_DEPTH - 1 downto 0) := (others => '0');
    begin
        if rst_n = '0' then
            sync_ff1  <= '1';
            sync_ff2  <= '1';
            shift_reg <= (others => '1');
            out_reg   <= '1';
        elsif rising_edge(clk) then
            -- Stage 1 & 2: 2-FF synchronizer
            sync_ff1 <= sig_norm;
            sync_ff2 <= sync_ff1;

            -- Stage 3: Glitch filter on synchronized signal
            shift_reg <= shift_reg(FILTER_DEPTH - 2 downto 0) & sync_ff2;

            if shift_reg = ALL_ONES then
                out_reg <= '1';
            elsif shift_reg = ALL_ZEROS then
                out_reg <= '0';
            end if;
        end if;
    end process;

    sig_out <= out_reg;

end architecture rtl;
