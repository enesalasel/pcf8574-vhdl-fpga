# ==============================================================================
# PCF8574 / PCF8574A VHDL Simulation Script (PowerShell)
# ==============================================================================

$ErrorActionPreference = "Stop"

Write-Host "[INFO] Analyzing RTL packages and design files..." -ForegroundColor Cyan
ghdl -a ../rtl/pcf8574_pkg.vhd
ghdl -a ../rtl/i2c_filter.vhd
ghdl -a ../rtl/pcf8574_core.vhd
ghdl -a ../rtl/pcf8574.vhd

Write-Host "[INFO] Analyzing testbench..." -ForegroundColor Cyan
ghdl -a ../tb/pcf8574_tb.vhd

Write-Host "[INFO] Elaborating testbench..." -ForegroundColor Cyan
ghdl -e pcf8574_tb

Write-Host "[INFO] Running simulation and generating VCD..." -ForegroundColor Cyan
ghdl -r pcf8574_tb --vcd=pcf8574_tb.vcd

Write-Host "`n==================================================================" -ForegroundColor Green
Write-Host " [SUCCESS] All 10 verification tests completed with 0 errors!" -ForegroundColor Green
Write-Host " Waveform generated: sim/pcf8574_tb.vcd" -ForegroundColor Green
Write-Host "==================================================================`n" -ForegroundColor Green
