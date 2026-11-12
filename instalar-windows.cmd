@echo off
rem Temas para Claude Desktop - Windows (BETA). Doble clic para instalar.
rem   instalar-windows.cmd -Theme mi-tema.json   cambia el tema
rem   instalar-windows.cmd -Uninstall            desinstala
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\instalar.ps1" %*
pause
