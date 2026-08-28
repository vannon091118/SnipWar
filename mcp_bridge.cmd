@echo off
rem ============================================================================
rem mcp_bridge.cmd -- cwd-immuner Starter fuer den SnipWar MCP-Stdio-Bridge.
rem
rem ROOT CAUSE (MCP-08, siehe docs/FINDINGS.md): Externe MCP-Clients loesen
rem relative Befehlszeilen gegen IHR eigenes cwd auf (z. B. %USERPROFILE%),
rem nicht gegen das Projektroot -- daraus wurde MODULE_NOT_FOUND.
rem
rem REGEL: In Client-Konfigurationen (z. B. Freebuff "choose tools") IMMER
rem diesen Wrapper mit ABSOLUTEM Pfad eintragen:
rem   C:\Users\Vannon\Documents\snippet-empire\snip-war\mcp_bridge.cmd
rem Der Wrapper leitet den Skriptpfad ueber %~dp0 (immer Projektroot) ab --
rem das cwd des Clients ist egal.
rem
rem Der Bridge ist zero-dependency (Python stdlib) und verbindet den laufenden
rem Spiel-Server auf TCP 127.0.0.1:9090 (env: MCP_HOST / MCP_PORT).
rem Spiel vorher sichtbar starten:
rem   $GODOT_BIN --path . -- --mcp --mcp-port 9090
rem ============================================================================
setlocal
python "%~dp0addons\gdscript_mcp\client\mcp_stdio_bridge.py" %*
