@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "ROOT=%~dp0.."
set "ALPOS=%ROOT%\alpos"
title setup

echo Folder: %cd%
echo This setup does not use PowerShell.
echo.

call :need_admin
if errorlevel 1 goto :done

call :ensure_jdk
if errorlevel 1 goto :done
call :import_cert
call :ensure_node
if errorlevel 1 goto :done
call :ensure_caddy
if errorlevel 1 goto :done
call :ensure_memurai
if errorlevel 1 goto :done
call :ensure_docker_app
if errorlevel 1 goto :done
call :ensure_nexus
if errorlevel 1 goto :done
call :ensure_repos
if errorlevel 1 goto :done
call :ensure_npm
if errorlevel 1 goto :done

docker version >nul 2>&1
if errorlevel 1 (
  echo Docker is installed but the engine is not running.
  echo Open Docker Desktop and wait for Engine running. If Windows just enabled WSL, reboot first.
  echo Then double-click Start-ImitationDev.cmd
  goto :done
)

echo.
echo Ready. Starting...
start "local-dev" /D "%~dp0." cmd /c Start-ImitationDev.cmd
goto :done

:need_admin
net session >nul 2>&1
if not errorlevel 1 exit /b 0
where winget >nul 2>&1
where git >nul 2>&1
where node >nul 2>&1
where docker >nul 2>&1
sc query Memurai >nul 2>&1
if errorlevel 1 (
  echo Some software is missing and installing it needs Administrator.
  echo Right-click Setup-And-Start.cmd and choose Run as administrator.
  echo After install, normal double-click is enough.
  exit /b 1
)
exit /b 0

:ensure_jdk
call :find_jdk
if defined JAVA_HOME exit /b 0
echo Installing JDK 25...
winget install --id Azul.Zulu.25.JDK -e --disable-interactivity --accept-package-agreements --accept-source-agreements
call :find_jdk
if not defined JAVA_HOME (
  echo JDK 25 was not found. Install Azul Zulu 25 and set JAVA_HOME, then run again.
  exit /b 1
)
setx JAVA_HOME "%JAVA_HOME%" >nul
echo JDK 25: %JAVA_HOME%
exit /b 0

:find_jdk
if defined JAVA_HOME if "%JAVA_HOME:~-1%"=="\" set "JAVA_HOME=%JAVA_HOME:~0,-1%"
set "JDK_CANDIDATE=%JAVA_HOME%"
set "JAVA_HOME="
if defined JDK_CANDIDATE call :jdk_match "%JDK_CANDIDATE%"
if defined JAVA_HOME exit /b 0
for /d %%D in ("C:\Program Files\Zulu\*") do call :jdk_match "%%D"
if defined JAVA_HOME exit /b 0
for /d %%D in ("C:\Program Files\Java\*") do call :jdk_match "%%D"
if defined JAVA_HOME exit /b 0
for /d %%D in ("C:\Program Files\Eclipse Adoptium\*") do call :jdk_match "%%D"
exit /b 0

:jdk_match
if defined JAVA_HOME exit /b 0
if not exist "%~1\release" exit /b 0
findstr /C:"JAVA_VERSION=" "%~1\release" | findstr /C:"25." >nul
if not errorlevel 1 set "JAVA_HOME=%~1"
exit /b 0

:import_cert
if not exist "%~dp0certs\mycas.crt" exit /b 0
if not exist "%JAVA_HOME%\bin\keytool.exe" exit /b 0
"%JAVA_HOME%\bin\keytool.exe" -list -alias mycas -cacerts -storepass changeit >nul 2>&1
if not errorlevel 1 (
  echo JDK already trusts mycas
  exit /b 0
)
echo Importing mycas into JDK...
"%JAVA_HOME%\bin\keytool.exe" -importcert -noprompt -alias mycas -cacerts -file "%~dp0certs\mycas.crt" -storepass changeit
exit /b 0

:ensure_node
where node >nul 2>&1
if not errorlevel 1 exit /b 0
echo Installing Node.js...
winget install --id OpenJS.NodeJS.LTS -e --disable-interactivity --accept-package-agreements --accept-source-agreements
where node >nul 2>&1
if errorlevel 1 (
  echo Node.js is not on PATH yet. Close this window and double-click again.
  exit /b 1
)
exit /b 0

:ensure_caddy
where caddy >nul 2>&1
if not errorlevel 1 exit /b 0
if exist "%LOCALAPPDATA%\Microsoft\WinGet\Packages\caddy.exe" exit /b 0
dir /s /b "%LOCALAPPDATA%\Microsoft\WinGet\Packages\caddy.exe" >nul 2>&1
if not errorlevel 1 exit /b 0
echo Installing Caddy...
winget install --id CaddyServer.Caddy -e --disable-interactivity --accept-package-agreements --accept-source-agreements
exit /b 0

:ensure_memurai
sc query Memurai >nul 2>&1
if not errorlevel 1 exit /b 0
echo Installing Memurai...
winget install --id Memurai.MemuraiDeveloper -e --disable-interactivity --accept-package-agreements --accept-source-agreements
sc query Memurai >nul 2>&1
if errorlevel 1 (
  echo Memurai is still missing. Run this file as administrator.
  exit /b 1
)
exit /b 0

:ensure_docker_app
where docker >nul 2>&1
if not errorlevel 1 exit /b 0
echo Installing Docker Desktop...
winget install --id Docker.DockerDesktop -e --disable-interactivity --accept-package-agreements --accept-source-agreements
where docker >nul 2>&1
if errorlevel 1 (
  echo Docker Desktop was installed. Reboot, open Docker Desktop, then double-click again.
  exit /b 1
)
exit /b 0

:ensure_nexus
set "PROPS=%USERPROFILE%\.gradle\gradle.properties"
if exist "%PROPS%" findstr /B /C:"systemProp.nexus.username=" "%PROPS%" >nul && findstr /B /C:"systemProp.nexus.password=" "%PROPS%" >nul && exit /b 0
echo.
echo This PC has no Nexus login. It is saved only in your user folder.
set /p NEXUS_USER=Nexus username: 
set /p NEXUS_PASS=Nexus password: 
if not exist "%USERPROFILE%\.gradle" mkdir "%USERPROFILE%\.gradle"
>>"%PROPS%" echo systemProp.nexus.group.url=https://nexus.alp.com.tw/repository/alp-public/
>>"%PROPS%" echo systemProp.nexus.username=%NEXUS_USER%
>>"%PROPS%" echo systemProp.nexus.password=%NEXUS_PASS%
echo Nexus settings saved.
exit /b 0

:ensure_repos
call :clone alpos https://git.alp.com.tw/alp/alpos.git springboot3
if errorlevel 1 exit /b 1
call :clone webapp https://git.alp.com.tw/alp/webapp.git
if errorlevel 1 exit /b 1
call :clone imitation-cas https://git.alp.com.tw/alp/imitation-cas.git
if errorlevel 1 exit /b 1
for %%P in (boss guts hulk loki oms magneto redhulk thor yaps ink kiss ares arms dos google-lib kafka-lib mars morph plus wanda zeus activiti-lib websocket-lib sync-data-lib microsoft-lib clean-lib) do (
  call :clone_into_alpos %%P
)
exit /b 0

:clone
if exist "%ROOT%\%~1\.git" (
  echo Already have %~1
  exit /b 0
)
echo Cloning %~1 ...
if "%~3"=="" (
  git clone "%~2" "%ROOT%\%~1"
) else (
  git clone -b "%~3" "%~2" "%ROOT%\%~1"
)
if errorlevel 1 (
  echo Could not clone %~1. Connect to VPN so git.alp.com.tw is reachable, then run again.
  exit /b 1
)
exit /b 0

:clone_into_alpos
if exist "%ALPOS%\%~1\.git" exit /b 0
echo Cloning %~1 ...
git clone "https://git.alp.com.tw/alp/%~1.git" "%ALPOS%\%~1"
exit /b 0

:ensure_npm
if exist "%ROOT%\webapp\node_modules" exit /b 0
echo npm install in webapp ...
cd /d "%ROOT%\webapp"
call npm install
if errorlevel 1 (
  echo npm install failed.
  exit /b 1
)
cd /d "%~dp0"
exit /b 0

:done
echo.
pause
endlocal
