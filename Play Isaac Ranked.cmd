@echo off
setlocal
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -NoProfile -Command ^
  "& { $launcher = Join-Path (Get-Location) 'launcher'; Set-Location $launcher; if (-not (Test-Path 'config.json')) { Copy-Item 'config.default.json' 'config.json' }; if (-not (Test-Path node_modules)) { npm install }; npm run play }"
if errorlevel 1 pause
