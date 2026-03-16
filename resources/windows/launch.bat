@echo off
:: launch.bat — Windows launcher for the IYAGI portable package.
::
:: Package layout (relative to this .bat file):
::   bin\dosbox.exe     — DOSBox-Staging binary
::   bin\bridge.exe     — TCP→SSH bridge binary
::   bin\plink.exe      — PuTTY command-line SSH client
::   bin\puttygen.exe   — PuTTY key generator
::   app\               — IYAGI 5.3 program files
::   dosbox.conf        — DOSBox configuration
::   .env               — connection settings (created on first run)
::   keys\              — SSH key files (created on first run)
::   downloads\         — received files (mapped as D: in DOSBox)

setlocal EnableDelayedExpansion

set "PKG=%~dp0"
set "DOSBOX=%PKG%bin\dosbox.exe"
set "BRIDGE=%PKG%bin\bridge.exe"
set "PLINK=%PKG%bin\plink.exe"
set "PUTTYGEN=%PKG%bin\puttygen.exe"
set "KEY_FILE=%PKG%keys\id_rsa.ppk"
set "BRIDGE_PORT=2323"

:: ─── Create required directories ───────────────────────────────────────────

if not exist "%PKG%keys\"      mkdir "%PKG%keys"
if not exist "%PKG%downloads\" mkdir "%PKG%downloads"

:: ─── Load user config (.env) ────────────────────────────────────────────────

if not exist "%PKG%.env" (
    copy "%PKG%.env.example" "%PKG%.env" >nul
    echo.
    echo === First run: created config at %PKG%.env
    echo     Edit it if needed: IYAGI_USER, ports.
    echo     Continuing with defaults for now.
    echo.
)

:: Parse KEY=VALUE pairs from .env (skip comment lines starting with #)
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%PKG%.env") do (
    set "%%A=%%B"
)

if not defined IYAGI_USER set "IYAGI_USER=user"
if not defined IYAGI_SSH_PORT set "IYAGI_SSH_PORT=22"
if not defined SSH_AUTH_MODE set "SSH_AUTH_MODE=bbs"
if not defined BRIDGE_BUSY_GAP_MS set "BRIDGE_BUSY_GAP_MS=0"
if not defined BRIDGE_DTMF_GAP_MS set "BRIDGE_DTMF_GAP_MS=320"
if not defined BRIDGE_POST_DTMF_DELAY_MS set "BRIDGE_POST_DTMF_DELAY_MS=500"
if not defined DOSBOX_CPU_CORE set "DOSBOX_CPU_CORE=simple"
if not defined DOSBOX_CPU_CPUTYPE set "DOSBOX_CPU_CPUTYPE=386"
if not defined DOSBOX_CPU_CYCLES set "DOSBOX_CPU_CYCLES=2000"
if not defined DOSBOX_SCANLINES set "DOSBOX_SCANLINES=1"
if not defined DOSBOX_GLSHADER set "DOSBOX_GLSHADER=crt/vga-1080p-fake-double-scan"
for /f "usebackq delims=" %%C in (`powershell -NoProfile -Command "$c='%DOSBOX_CPU_CYCLES%'; if($c -match '^[0-9]+$'){ 'fixed ' + $c } else { $c }"`) do (
    set "DOSBOX_CPU_CYCLES_SET=%%C"
)
for /f %%S in ('powershell -NoProfile -Command "$v='%DOSBOX_SCANLINES%'.ToLower(); if($v -in @('1','true','yes','on')){'1'} else {'0'}"') do set "DOSBOX_SCANLINES_ENABLED=%%S"
if "%DOSBOX_SCANLINES_ENABLED%"=="1" (
    set "DOSBOX_OUTPUT=opengl"
    set "DOSBOX_GLSHADER_SET=%DOSBOX_GLSHADER%"
    set "DOSBOX_INTEGER_SCALING=vertical"
) else (
    set "DOSBOX_OUTPUT=texture"
    set "DOSBOX_GLSHADER_SET=none"
    set "DOSBOX_INTEGER_SCALING=auto"
)
if defined BRIDGE_PORT_ENV set "BRIDGE_PORT=%BRIDGE_PORT_ENV%"
set "ORIGINAL_BRIDGE_PORT=%BRIDGE_PORT%"
for /f %%P in ('powershell -NoProfile -Command "$p='%BRIDGE_PORT%';function Get-FreePort{$l=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse(\"127.0.0.1\"),0);$l.Start();$n=$l.LocalEndpoint.Port;$l.Stop();return $n};if([string]::IsNullOrWhiteSpace($p) -or $p -eq 'auto'){Write-Output (Get-FreePort);exit};try{$l=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse(\"127.0.0.1\"),[int]$p);$l.Start();$l.Stop();Write-Output $p}catch{Write-Output (Get-FreePort)}"') do (
    set "BRIDGE_PORT=%%P"
)
if /I "%ORIGINAL_BRIDGE_PORT%"=="auto" (
    echo Selected bridge port automatically: %BRIDGE_PORT%
) else if not "%ORIGINAL_BRIDGE_PORT%"=="%BRIDGE_PORT%" (
    echo Configured BRIDGE_PORT=%ORIGINAL_BRIDGE_PORT% is in use; switched to free port: %BRIDGE_PORT%
)
if not defined DOSBOX_MODEM_LISTENPORT set "DOSBOX_MODEM_LISTENPORT=auto"
set "APP_DIR=%PKG%app"

if /I "%DOSBOX_MODEM_LISTENPORT%"=="auto" (
    for /f %%P in ('powershell -NoProfile -Command "$l=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse(\"127.0.0.1\"),0);$l.Start();$p=$l.LocalEndpoint.Port;$l.Stop();Write-Output $p"') do (
        set "DOSBOX_MODEM_LISTENPORT=%%P"
    )
)
echo Using DOSBox modem listenport: %DOSBOX_MODEM_LISTENPORT%

powershell -NoProfile -Command "$conf='%PKG%dosbox.conf';$lp='%DOSBOX_MODEM_LISTENPORT%';$serial='serial1=modem listenport:' + $lp;$text=Get-Content -Raw -Path $conf;if($text -match '(?m)^\s*serial1\s*='){ $text=[regex]::Replace($text,'(?m)^\s*serial1\s*=.*$',$serial)} else {$text += \"`r`n[serial]`r`n$serial`r`n\"};if($text -match '(?m)^\s*mouse_capture\s*='){ $text=[regex]::Replace($text,'(?m)^\s*mouse_capture\s*=.*$','mouse_capture=nomouse')} else {$text += \"`r`n[mouse]`r`nmouse_capture=nomouse`r`n\"};if($text -match '(?m)^\s*mouse_middle_release\s*='){ $text=[regex]::Replace($text,'(?m)^\s*mouse_middle_release\s*=.*$','mouse_middle_release=false')} else {if($text -notmatch '(?s)\[mouse\]'){ $text += \"`r`n[mouse]`r`n\"};$text += 'mouse_middle_release=false`r`n'};if($text -match '(?m)^\s*dos_mouse_driver\s*='){ $text=[regex]::Replace($text,'(?m)^\s*dos_mouse_driver\s*=.*$','dos_mouse_driver=false')} else {if($text -notmatch '(?s)\[mouse\]'){ $text += \"`r`n[mouse]`r`n\"};$text += 'dos_mouse_driver=false`r`n'};if($text -match '(?m)^\s*texture_renderer\s*='){ $text=[regex]::Replace($text,'(?m)^\s*texture_renderer\s*=.*$','texture_renderer=auto')} else {if($text -notmatch '(?s)\[sdl\]'){ $text += \"`r`n[sdl]`r`n\"};$text += 'texture_renderer=auto`r`n'};Set-Content -Path $conf -Value $text -NoNewline"

:: ─── First-run SSH key setup ────────────────────────────────────────────────

if /I "%SSH_AUTH_MODE%"=="key" if not exist "%KEY_FILE%" (
    echo.
    echo === First run: generating SSH key pair ===
    "%PUTTYGEN%" -t rsa -b 4096 -o "%KEY_FILE%" --comment "iyagi-terminal"
    echo.
    echo NOTE: Add the public key below to your SSH server's ~/.ssh/authorized_keys:
    echo.
    "%PUTTYGEN%" -L "%KEY_FILE%"
    echo.
    pause
)

:: ─── Start the bridge ───────────────────────────────────────────────────────

set "SSH_TEMPLATE=%PLINK% -P {port} -i ""%KEY_FILE%"" {userhost}"

set "BRIDGE_PORT=%BRIDGE_PORT%"
set "BRIDGE_CMD="
set "BRIDGE_CMD_TEMPLATE=%SSH_TEMPLATE%"
set "BRIDGE_SSH_USER=%IYAGI_USER%"
set "BRIDGE_BUSY_GAP_MS=%BRIDGE_BUSY_GAP_MS%"
set "BRIDGE_DTMF_GAP_MS=%BRIDGE_DTMF_GAP_MS%"
set "BRIDGE_POST_DTMF_DELAY_MS=%BRIDGE_POST_DTMF_DELAY_MS%"
start "IYAGI Bridge" /b "%BRIDGE%"

timeout /t 2 >nul

:: ─── Run DOSBox ─────────────────────────────────────────────────────────────
:: dosbox.conf uses relative paths (./app, ./downloads) so we run from PKG root.

pushd "%PKG%"
"%DOSBOX%" -conf dosbox.conf -noconsole -set "core=%DOSBOX_CPU_CORE%" -set "cputype=%DOSBOX_CPU_CPUTYPE%" -set "cpu_cycles=%DOSBOX_CPU_CYCLES_SET%" -set "startup_verbosity=quiet" -set "output=%DOSBOX_OUTPUT%" -set "glshader=%DOSBOX_GLSHADER_SET%" -set "integer_scaling=%DOSBOX_INTEGER_SCALING%" -set "ne2000=false" -set "texture_renderer=auto" -set "mouse_capture=nomouse" -set "mouse_middle_release=false" -set "dos_mouse_driver=false"
popd

:: ─── Cleanup ────────────────────────────────────────────────────────────────

taskkill /f /im bridge.exe >nul 2>&1
taskkill /f /im plink.exe  >nul 2>&1

endlocal
