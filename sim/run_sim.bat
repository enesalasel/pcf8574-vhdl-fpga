@echo off
rem ============================================================================
rem  PCF8574 / PCF8574A VHDL Simulation Script using GHDL
rem ============================================================================

echo [INFO] Analyzing RTL packages and design files...
ghdl -a ../rtl/pcf8574_pkg.vhd
if %ERRORLEVEL% neq 0 goto error
ghdl -a ../rtl/i2c_filter.vhd
if %ERRORLEVEL% neq 0 goto error
ghdl -a ../rtl/pcf8574_core.vhd
if %ERRORLEVEL% neq 0 goto error
ghdl -a ../rtl/pcf8574.vhd
if %ERRORLEVEL% neq 0 goto error

echo [INFO] Analyzing testbench...
ghdl -a ../tb/pcf8574_tb.vhd
if %ERRORLEVEL% neq 0 goto error

echo [INFO] Elaborating testbench entity: pcf8574_tb...
ghdl -e pcf8574_tb
if %ERRORLEVEL% neq 0 goto error

echo [INFO] Running simulation and generating VCD waveform...
ghdl -r pcf8574_tb --vcd=pcf8574_tb.vcd
if %ERRORLEVEL% neq 0 goto error

echo.
echo ============================================================================
echo  [SUCCESS] All verification tests passed! Waveform saved to pcf8574_tb.vcd
echo ============================================================================
goto end

:error
echo.
echo [ERROR] Simulation failed! Check error messages above.
exit /b 1

:end
