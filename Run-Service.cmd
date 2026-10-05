@echo off
setlocal
cd /d "%~dp0"
set "ROOT=%~dp0.."
set "ALPOS=%ROOT%\alpos"
set "HERE=%~dp0"
if "%GRADLE_USER_HOME%"=="" set "GRADLE_USER_HOME=%USERPROFILE%\.gradle"

if /I "%~1"=="caddy" goto :caddy
if /I "%~1"=="sys" goto :sys
if /I "%~1"=="oms" goto :oms
echo Usage: Run-Service.cmd caddy^|sys^|oms
exit /b 1

:java
if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" goto :java_ok
for /f "tokens=2*" %%A in ('reg query HKCU\Environment /v JAVA_HOME 2^>nul') do set "JAVA_HOME=%%B"
if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" goto :java_ok
echo JDK 25 not found. Set JAVA_HOME and run again.
pause
exit /b 1
:java_ok
exit /b 0

:caddy
set "CADDY="
for /f "delims=" %%C in ('where caddy 2^>nul') do if not defined CADDY set "CADDY=%%C"
if not defined CADDY (
  for /f "delims=" %%C in ('dir /s /b "%LOCALAPPDATA%\Microsoft\WinGet\Packages\caddy.exe" 2^>nul') do if not defined CADDY set "CADDY=%%C"
)
if not defined CADDY (
  echo caddy.exe not found.
  pause
  exit /b 1
)
"%CADDY%" run --config "%HERE%Caddyfile" --adapter caddyfile
exit /b %ERRORLEVEL%

:sys
call :java
if errorlevel 1 exit /b 1
call :jar sys
if errorlevel 1 exit /b 1
call :dotenv "%HERE%alpos.env"
cd /d "%ALPOS%\sys"
"%JAVA_HOME%\bin\java.exe" -Duser.timezone=Asia/Taipei -Dfile.encoding=UTF-8 -Djava.net.preferIPv4Stack=true -jar "%JAR%" --server.http.port=0
exit /b %ERRORLEVEL%

:oms
call :java
if errorlevel 1 exit /b 1
call :jar oms
if errorlevel 1 exit /b 1
call :dotenv "%HERE%alpos.env"
cd /d "%ALPOS%\oms"
"%JAVA_HOME%\bin\java.exe" -Duser.timezone=Asia/Taipei -Dfile.encoding=UTF-8 -Djava.net.preferIPv4Stack=true -jar "%JAR%"
exit /b %ERRORLEVEL%

:jar
set "MOD=%~1"
set "JAR="
if not exist "%ALPOS%\%MOD%\build\libs\*.jar" (
  echo Building %MOD% ...
  cd /d "%ALPOS%"
  call gradlew.bat ":%MOD%:bootJar" -x test --console=plain
  if errorlevel 1 (
    echo Build failed: %MOD%
    pause
    exit /b 1
  )
)
for /f "delims=" %%J in ('dir /b /o-d "%ALPOS%\%MOD%\build\libs\*.jar"') do (
  echo %%J | findstr /I /C:"-plain.jar" >nul
  if errorlevel 1 if not defined JAR set "JAR=%ALPOS%\%MOD%\build\libs\%%J"
)
if not defined JAR (
  echo No jar for %MOD%
  pause
  exit /b 1
)
exit /b 0

:dotenv
if not exist "%~1" exit /b 0
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%~1") do set "%%A=%%B"
exit /b 0
