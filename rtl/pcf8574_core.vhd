--------------------------------------------------------------------------------
-- Project: PCF8574 / PCF8574A Remote 8-Bit I/O Expander for I2C-Bus
-- File   : pcf8574_core.vhd
-- Description: Core logic implementing I2C slave protocol, address decoding,
--              quasi-bidirectional port register, and interrupt generation.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pcf8574_pkg.all;

entity pcf8574_core is
    generic (
        ADDR_PREFIX  : std_logic_vector(3 downto 0) := PCF8574_ADDR_PREFIX;
        FILTER_DEPTH : natural := 3
    );
    port (
        clk            : in  std_logic;
        rst_n          : in  std_logic;
        -- Hardware Address Pins (A0, A1, A2)
        a              : in  std_logic_vector(2 downto 0);
        -- I2C Bus Interface
        scl_in         : in  std_logic;
        sda_in         : in  std_logic;
        sda_drive_low  : out std_logic;
        -- Quasi-Bidirectional Port Interface
        port_pin_in    : in  std_logic_vector(7 downto 0);
        port_drive_low : out std_logic_vector(7 downto 0);
        -- Interrupt Output (Active-low drive signal)
        int_drive_low  : out std_logic
    );
end entity pcf8574_core;

architecture rtl of pcf8574_core is

    -- Filtered bus signals
    signal scl_filt : std_logic;
    signal sda_filt : std_logic;
    signal scl_d    : std_logic := '1';
    signal sda_d    : std_logic := '1';

    -- Edge detection pulses
    signal scl_rising    : std_logic;
    signal scl_falling   : std_logic;
    signal sda_rising    : std_logic;
    signal sda_falling   : std_logic;

    -- Bus condition signals
    signal start_detected : std_logic;
    signal stop_detected  : std_logic;

    -- Filtered port pins
    signal port_pin_filt : std_logic_vector(7 downto 0);

    -- Internal port latch (Quasi-bidirectional output register)
    signal port_reg : std_logic_vector(7 downto 0) := POR_PORT_DEFAULT;

    -- Interrupt baseline snapshot
    signal port_snapshot : std_logic_vector(7 downto 0) := POR_PORT_DEFAULT;
    signal pulse_clear_int_read  : std_logic := '0';
    signal pulse_clear_int_write : std_logic := '0';

    -- I2C FSM and Shift Registers
    signal state         : t_i2c_fsm_state := ST_IDLE;
    signal bit_cnt       : integer range 0 to 8 := 0;
    signal rx_shift_reg  : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_shift_reg  : std_logic_vector(7 downto 0) := (others => '0');
    signal write_latch   : std_logic_vector(7 downto 0) := (others => '0');
    signal rw_mode       : std_logic := '0'; -- '0' = Write, '1' = Read

    -- Address to match: 4-bit prefix & A2 & A1 & A0
    signal device_addr   : std_logic_vector(6 downto 0);

    -- Internal SDA drive control
    signal sda_drv : std_logic := '0';

begin

    -- Assemble 7-bit device address
    device_addr <= ADDR_PREFIX & a(2) & a(1) & a(0);

    ----------------------------------------------------------------------------
    -- 1. Input Glitch Filters
    ----------------------------------------------------------------------------
    u_scl_filter : i2c_filter
        generic map ( FILTER_DEPTH => FILTER_DEPTH )
        port map (
            clk     => clk,
            rst_n   => rst_n,
            sig_in  => scl_in,
            sig_out => scl_filt
        );

    u_sda_filter : i2c_filter
        generic map ( FILTER_DEPTH => FILTER_DEPTH )
        port map (
            clk     => clk,
            rst_n   => rst_n,
            sig_in  => sda_in,
            sig_out => sda_filt
        );

    gen_port_filters: for i in 0 to 7 generate
        u_p_filter : i2c_filter
            generic map ( FILTER_DEPTH => FILTER_DEPTH )
            port map (
                clk     => clk,
                rst_n   => rst_n,
                sig_in  => port_pin_in(i),
                sig_out => port_pin_filt(i)
            );
    end generate;

    ----------------------------------------------------------------------------
    -- 2. Edge and Bus Condition Detectors
    ----------------------------------------------------------------------------
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            scl_d <= '1';
            sda_d <= '1';
        elsif rising_edge(clk) then
            scl_d <= scl_filt;
            sda_d <= sda_filt;
        end if;
    end process;

    scl_rising  <= '1' when (scl_filt = '1' and scl_d = '0') else '0';
    scl_falling <= '1' when (scl_filt = '0' and scl_d = '1') else '0';
    sda_rising  <= '1' when (sda_filt = '1' and sda_d = '0') else '0';
    sda_falling <= '1' when (sda_filt = '0' and sda_d = '1') else '0';

    -- START condition: SDA falling while SCL is high
    start_detected <= '1' when (sda_falling = '1' and scl_filt = '1') else '0';

    -- STOP condition: SDA rising while SCL is high
    stop_detected  <= '1' when (sda_rising = '1' and scl_filt = '1') else '0';

    ----------------------------------------------------------------------------
    -- 3. I2C Slave Protocol Engine (Finite State Machine)
    ----------------------------------------------------------------------------
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            state                 <= ST_IDLE;
            bit_cnt               <= 0;
            rx_shift_reg          <= (others => '0');
            tx_shift_reg          <= (others => '0');
            write_latch           <= (others => '0');
            port_reg              <= POR_PORT_DEFAULT;
            rw_mode               <= '0';
            sda_drv               <= '0';
            pulse_clear_int_read  <= '0';
            pulse_clear_int_write <= '0';
        elsif rising_edge(clk) then
            -- Default single-cycle pulse resets
            pulse_clear_int_read  <= '0';
            pulse_clear_int_write <= '0';

            -- Asynchronous START condition overrides current state (Repeated START supported)
            if start_detected = '1' then
                state   <= ST_ADDR;
                bit_cnt <= 0;
                sda_drv <= '0';
            -- Asynchronous STOP condition returns bus to IDLE
            elsif stop_detected = '1' then
                state   <= ST_IDLE;
                bit_cnt <= 0;
                sda_drv <= '0';
            else
                case state is

                    ------------------------------------------------------------
                    -- Idle: waiting for START
                    ------------------------------------------------------------
                    when ST_IDLE =>
                        sda_drv <= '0';
                        bit_cnt <= 0;

                    ------------------------------------------------------------
                    -- Shift in 7-bit Address + 1-bit R/W
                    ------------------------------------------------------------
                    when ST_ADDR =>
                        sda_drv <= '0';
                        if scl_rising = '1' then
                            rx_shift_reg <= rx_shift_reg(6 downto 0) & sda_filt;
                            bit_cnt      <= bit_cnt + 1;
                        elsif scl_falling = '1' then
                            if bit_cnt = 8 then
                                -- Strict 7-bit hardware address match (no hardcoding)
                                if rx_shift_reg(7 downto 1) = device_addr then
                                    rw_mode <= rx_shift_reg(0);
                                    sda_drv <= '1'; -- Drive ACK (LOW)
                                    state   <= ST_ADDR_ACK;
                                else
                                    -- Address mismatch: ignore remainder of transaction
                                    sda_drv <= '0';
                                    state   <= ST_WAIT_STOP;
                                end if;
                                bit_cnt <= 0;
                            end if;
                        end if;

                    ------------------------------------------------------------
                    -- Acknowledge Address byte
                    ------------------------------------------------------------
                    when ST_ADDR_ACK =>
                        -- SDA is held LOW during this 9th clock pulse
                        if scl_falling = '1' then
                            bit_cnt <= 0;
                            if rw_mode = '0' then
                                -- Master write mode
                                sda_drv <= '0'; -- Release SDA to receive data
                                state   <= ST_WRITE_DATA;
                            else
                                -- Master read mode: sample current pins into TX shift register
                                tx_shift_reg <= port_pin_filt;
                                -- Output MSB (bit 7)
                                if port_pin_filt(7) = '0' then
                                    sda_drv <= '1'; -- Drive LOW
                                else
                                    sda_drv <= '0'; -- Release (HIGH)
                                end if;
                                state <= ST_READ_DATA;
                            end if;
                        end if;

                    ------------------------------------------------------------
                    -- Receive 8-bit Data from Master (Write Mode)
                    ------------------------------------------------------------
                    when ST_WRITE_DATA =>
                        sda_drv <= '0';
                        if scl_rising = '1' then
                            rx_shift_reg <= rx_shift_reg(6 downto 0) & sda_filt;
                            bit_cnt      <= bit_cnt + 1;
                        elsif scl_falling = '1' then
                            if bit_cnt = 8 then
                                write_latch <= rx_shift_reg;
                                sda_drv     <= '1'; -- Drive ACK (LOW)
                                state       <= ST_WRITE_ACK;
                                bit_cnt     <= 0;
                            end if;
                        end if;

                    ------------------------------------------------------------
                    -- Acknowledge Written Data Byte
                    ------------------------------------------------------------
                    when ST_WRITE_ACK =>
                        -- In write mode, interrupt resets at the falling edge of SCL of ACK bit
                        if scl_falling = '1' then
                            port_reg              <= write_latch; -- Update output ports
                            pulse_clear_int_write <= '1';         -- Clear interrupt
                            sda_drv               <= '0';         -- Release SDA
                            bit_cnt               <= 0;
                            -- Stay ready for consecutive bytes if master keeps transmitting
                            state                 <= ST_WRITE_DATA;
                        end if;

                    ------------------------------------------------------------
                    -- Transmit 8-bit Data to Master (Read Mode)
                    ------------------------------------------------------------
                    when ST_READ_DATA =>
                        if scl_rising = '1' then
                            bit_cnt <= bit_cnt + 1;
                        elsif scl_falling = '1' then
                            if bit_cnt < 8 then
                                -- Shift and drive next bit
                                tx_shift_reg <= tx_shift_reg(6 downto 0) & '1';
                                if tx_shift_reg(6) = '0' then
                                    sda_drv <= '1';
                                else
                                    sda_drv <= '0';
                                end if;
                            else
                                -- 8 bits sent: release SDA for Master's ACK/NACK
                                sda_drv <= '0';
                                state   <= ST_READ_ACK;
                                bit_cnt <= 0;
                            end if;
                        end if;

                    ------------------------------------------------------------
                    -- Sample Master's ACK/NACK (Read Mode)
                    ------------------------------------------------------------
                    when ST_READ_ACK =>
                        -- In read mode, interrupt resets at the rising edge of SCL of ACK bit
                        if scl_rising = '1' then
                            pulse_clear_int_read <= '1';
                            if sda_filt = '0' then
                                -- Master ACK: wants another byte
                                rw_mode <= '1';
                            else
                                -- Master NACK: end of read
                                rw_mode <= '0';
                            end if;
                        elsif scl_falling = '1' then
                            if rw_mode = '1' then
                                -- Sample current pins again for the next byte
                                tx_shift_reg <= port_pin_filt;
                                if port_pin_filt(7) = '0' then
                                    sda_drv <= '1';
                                else
                                    sda_drv <= '0';
                                end if;
                                bit_cnt <= 0;
                                state   <= ST_READ_DATA;
                            else
                                -- Master NACK received: release SDA and wait for STOP
                                sda_drv <= '0';
                                state   <= ST_WAIT_STOP;
                            end if;
                        end if;

                    ------------------------------------------------------------
                    -- Wait for STOP Condition
                    ------------------------------------------------------------
                    when ST_WAIT_STOP =>
                        sda_drv <= '0';
                        -- Handled by stop_detected or start_detected

                end case;
            end if;
        end if;
    end process;

    sda_drive_low <= sda_drv;

    ----------------------------------------------------------------------------
    -- 4. Quasi-Bidirectional Port Output Control
    ----------------------------------------------------------------------------
    -- When port_reg(i) = '0', drive pin LOW.
    -- When port_reg(i) = '1', release pin (weak pull-up / High-Z allows external input).
    gen_port_drive: for i in 0 to 7 generate
        port_drive_low(i) <= '1' when (port_reg(i) = '0') else '0';
    end generate;

    ----------------------------------------------------------------------------
    -- 5. Interrupt Generation & Clearing Logic
    ----------------------------------------------------------------------------
    -- An interrupt is triggered whenever any input pin (configured with port_reg='1')
    -- differs from the baseline snapshot.
    -- Reset occurs when:
    -- 1) Pin returns to previous state.
    -- 2) Read ACK occurs (pulse_clear_int_read).
    -- 3) Write ACK occurs (pulse_clear_int_write).
    process(clk, rst_n)
        variable active_inputs_changed : boolean;
    begin
        if rst_n = '0' then
            port_snapshot <= POR_PORT_DEFAULT;
            int_drive_low <= '0';
        elsif rising_edge(clk) then
            if pulse_clear_int_read = '1' then
                port_snapshot <= port_pin_filt;
                int_drive_low <= '0';
            elsif pulse_clear_int_write = '1' then
                port_snapshot <= write_latch;
                int_drive_low <= '0';
            else
                -- Check for mismatch only on pins acting as inputs (port_reg = '1')
                active_inputs_changed := false;
                for i in 0 to 7 loop
                    if port_reg(i) = '1' then
                        if port_pin_filt(i) /= port_snapshot(i) then
                            active_inputs_changed := true;
                        end if;
                    end if;
                end loop;

                if active_inputs_changed then
                    int_drive_low <= '1'; -- Pull INT_N low
                else
                    int_drive_low <= '0'; -- High-Z
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
