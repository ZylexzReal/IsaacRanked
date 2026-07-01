@echo off
setlocal
powershell -ExecutionPolicy Bypass -File "%~dp0start-bridge-agent.ps1" %*
