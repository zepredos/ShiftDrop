@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-windows.ps1"
set "install_result=%errorlevel%"
if not "%install_result%"=="0" echo Installation failed. See the message above.
pause
exit /b %install_result%
