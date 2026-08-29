@echo off
rem ============================================================================
rem mcp_start.cmd -- Sichtbare SnipWar-Runtime mit MCP-Server starten.
rem  MCP braucht einen echten Renderer: Headless wird vom Server verweigert.
rem  Nutzung: mcp_start.cmd [player|qa|dev]   (Standard: player)
rem  Port:    127.0.0.1:9090 (Runtime) | 9091 (Editor).
rem ============================================================================
setlocal
set PROFILE=%~1
if "%PROFILE%"=="" set PROFILE=player

set BIN=%GODOT_BIN%
if "%BIN%"=="" set BIN=C:\Users\Vannon\Desktop\godu\Godot_v4.7.2-stable_win64_console.exe
if not exist "%BIN%" (
  echo GODOT_BIN nicht auffindbar: %BIN%
  exit /b 1
)

rem Listener-Check (Skill mcp-connect): nie doppelt starten.
netstat -ano | findstr /R /C:"TCP.*:9090 .*LISTENING" >nul
if %errorlevel%==0 (
  echo Port 9090 lauscht bereits -- bestehenden Runtime/Editor verwenden.
  exit /b 0
)

echo Starte sichtbare Runtime mit MCP auf 127.0.0.1:9090 (Profil=%PROFILE%) ...
"%BIN%" --path %CD% -- --mcp --mcp-port 9090 --mcp-profile=%PROFILE%