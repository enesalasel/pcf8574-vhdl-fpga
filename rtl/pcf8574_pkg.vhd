--------------------------------------------------------------------------------
-- Project: PCF8574 / PCF8574A Remote 8-Bit I/O Expander for I2C-Bus
-- File   : pcf8574_pkg.vhd
-- Description: Package containing constants, types, and component declarations
--              for the PCF8574 I2C I/O expander.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package pcf8574_pkg is

    -- Standard 4-bit fixed address prefixes
    -- PCF8574  fixed prefix: "0100" (Base addresses 0x20 to 0x27)
    -- PCF8574A fixed prefix: "0111" (Base addresses 0x38 to 0x3F)
    constant PCF8574_ADDR_PREFIX  : std_logic_vector(3 downto 0) := "0100";
    constant PCF8574A_ADDR_PREFIX : std_logic_vector(3 downto 0) := "0111";

    -- Power-on reset default values
    constant POR_PORT_DEFAULT     : std_logic_vector(7 downto 0) := "11111111"; -- 0xFF (Quasi-bidirectional inputs)

    -- I2C Protocol state machine types
    type t_i2c_fsm_state is (
        ST_IDLE,          -- Bus idle, waiting for START condition
        ST_ADDR,          -- Receiving 7 address bits + 1 R/W bit
        ST_ADDR_ACK,      -- Driving ACK if address matched, or releasing bus
        ST_WRITE_DATA,    -- Receiving 8 data bits from master
        ST_WRITE_ACK,     -- Driving ACK to master and updating port register
        ST_READ_DATA,     -- Transmitting 8 data bits (sampled port) to master
        ST_READ_ACK,      -- Sampling ACK/NACK from master
        ST_WAIT_STOP      -- Waiting for STOP or repeated START condition
    );

    -- Component declaration for Glitch Filter
    component i2c_filter is
        generic (
            FILTER_DEPTH : natural := 3
        );
        port (
            clk     : in  std_logic;
            rst_n   : in  std_logic;
            sig_in  : in  std_logic;
            sig_out : out std_logic
        );
    end component;

    -- Component declaration for PCF8574 Core Logic
    component pcf8574_core is
        generic (
            ADDR_PREFIX  : std_logic_vector(3 downto 0) := PCF8574_ADDR_PREFIX;
            FILTER_DEPTH : natural := 3
        );
        port (
            clk           : in  std_logic;
            rst_n         : in  std_logic;
            a             : in  std_logic_vector(2 downto 0);
            scl_in        : in  std_logic;
            sda_in        : in  std_logic;
            sda_drive_low : out std_logic;
            port_pin_in   : in  std_logic_vector(7 downto 0);
            port_drive_low: out std_logic_vector(7 downto 0);
            int_drive_low : out std_logic
        );
    end component;

    -- Component declaration for Pure Board-Agnostic PCF8574 Top Level
    component pcf8574 is
        generic (
            ADDR_PREFIX       : std_logic_vector(3 downto 0) := PCF8574_ADDR_PREFIX;
            FILTER_DEPTH      : natural := 3;
            ENABLE_RISE_BOOST : boolean := false
        );
        port (
            clk          : in    std_logic;
            rst_n        : in    std_logic := '1';
            a0           : in    std_logic;
            a1           : in    std_logic;
            a2           : in    std_logic;
            scl          : in    std_logic;
            sda          : inout std_logic;
            p            : inout std_logic_vector(7 downto 0);
            int_n        : out   std_logic
        );
    end component;

end package pcf8574_pkg;

package body pcf8574_pkg is
end package body pcf8574_pkg;
