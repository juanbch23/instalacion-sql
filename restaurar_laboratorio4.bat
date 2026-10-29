@echo off
rem Doble clic: restaura el laboratorio 4 en tu SQL Server (detecta todo solo).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restaurar_laboratorio4.ps1" %*
echo.
pause
