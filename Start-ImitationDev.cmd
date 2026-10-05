@echo off
setlocal
cd /d "%~dp0"
title local-dev

echo [1/4] Memurai
"%SystemRoot%\System32\sc.exe" query Memurai | "%SystemRoot%\System32\findstr.exe" /I "RUNNING" >nul
if errorlevel 1 (
  echo Memurai is not running. Trying to start it...
  "%SystemRoot%\System32\net.exe" start Memurai
  if errorlevel 1 (
    echo Could not start Memurai. Open an administrator PowerShell and run: net start Memurai
    pause
    exit /b 1
  )
)

echo [2/4] Caddy sys oms
start "caddy" /D "%~dp0." cmd /k Run-Service.cmd caddy
start "sys" /D "%~dp0." cmd /k Run-Service.cmd sys
start "oms" /D "%~dp0." cmd /k Run-Service.cmd oms

echo [3/4] imitation-cas
docker version >nul 2>&1
if errorlevel 1 (
  echo Docker engine is not running. Open Docker Desktop, wait until Engine running, then run this file again.
  echo The Caddy, sys and oms windows can stay open.
  pause
  exit /b 1
)
if /I "%~1"=="build" (
  docker compose -f "..\imitation-cas\docker-compose.yml" -f "imitation-cas.override.yml" up --build -d
) else (
  docker compose -f "..\imitation-cas\docker-compose.yml" -f "imitation-cas.override.yml" up -d
)
if errorlevel 1 (
  echo imitation-cas failed. See the error above.
  pause
  exit /b 1
)

echo [4/4] webapp
start "webapp" /D "%~dp0..\webapp" cmd /k npx cross-env url=local sysCode=oms rsbuild dev
echo.
echo Started. Wait until the sys and oms windows say Started Application.
echo Frontend: http://localhost:3000    choose imitation CAS login
echo Swagger:  http://localhost:8081/swagger-ui.html
echo.
echo Close the caddy, sys, oms and webapp windows to stop them.
echo Stop imitation-cas with:
echo   docker compose -f ..\imitation-cas\docker-compose.yml -f imitation-cas.override.yml down
pause
endlocal
