@echo off
set PYTHONHOME=C:\Users\Vannon\AppData\Local\Programs\Python\Python312
set PYTHONPATH=%PYTHONHOME%\Lib
"%PYTHONHOME%\python.exe" addons/gdscript_mcp/client/mcp_client.py --port 9090 --one-shot
