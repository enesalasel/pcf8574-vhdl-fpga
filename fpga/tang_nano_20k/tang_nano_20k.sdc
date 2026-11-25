// =============================================================================
// Timing Constraints (.sdc) for Sipeed Tang Nano 20K (27 MHz System Clock)
// =============================================================================

// 27 MHz onboard crystal clock (Period = 37.037 ns)
create_clock -name clk -period 37.037 -waveform {0 18.518} [get_ports {clk}]

// Asynchronous external I2C, address, GPIO, and LED pads
// (Synchronized internally via 2-FF synchronizers + glitch filters)
set_false_path -from [get_ports {a0 a1 a2 scl sda p[*]}]
set_false_path -to   [get_ports {sda p[*] int_n led_n[*]}]
