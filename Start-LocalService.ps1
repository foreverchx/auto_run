# Starts one local-dev service in the current console.
#   .\Start-LocalService.ps1 caddy   # https://localhost:8443 reverse proxy (start first)
#   .\Start-LocalService.ps1 cas     # :9443  (needs Redis on 6379)
#   .\Start-LocalService.ps1 klaw    # :9444
#   .\Start-LocalService.ps1 sys     # :8890
#   .\Start-LocalService.ps1 oms     # :8889
# Add -Build to rebuild the alpos boot jar before starting (do not run several -Build at once:
# they share the alpos build directory).
param(
  [Parameter(Mandatory)][ValidateSet('caddy', 'cas', 'klaw', 'sys', 'oms')][string]$Name,
  [switch]$Build
)
$here  = $PSScriptRoot
$root  = (Resolve-Path "$here\..").Path
$alpos = "$root\alpos"

function Import-DotEnv([string]$path) {
  if (-not (Test-Path $path)) { return }
  foreach ($line in [IO.File]::ReadAllLines($path)) {
    if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
    $k, $v = $line -split '=', 2
    [Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim().Trim("'").Trim('"'), 'Process')
  }
}

function Find-Jdk25 {
  if ($env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\release") -and
      (Select-String -Path "$env:JAVA_HOME\release" -Pattern 'JAVA_VERSION="25' -Quiet)) { return $env:JAVA_HOME }
  $userHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
  if ($userHome -and (Test-Path "$userHome\bin\java.exe")) { return $userHome }
  throw 'JDK 25 not found: set JAVA_HOME to the JDK 25 directory.'
}

function Start-AlposJar([string]$module, [string[]]$extraArgs) {
  if ($Build -or -not (Get-ChildItem "$alpos\$module\build\libs" -Filter *.jar -ErrorAction SilentlyContinue)) {
    Push-Location $alpos
    try { & .\gradlew.bat ":${module}:bootJar" -x test --console=plain; if ($LASTEXITCODE) { throw "build failed" } }
    finally { Pop-Location }
  }
  $jar = Get-ChildItem "$alpos\$module\build\libs" -Filter *.jar |
    Where-Object { $_.Name -notmatch '-plain\.jar$' } | Sort-Object LastWriteTime | Select-Object -Last 1
  Push-Location "$alpos\$module"
  $jvmArgs = @('-Duser.timezone=Asia/Taipei', '-Dfile.encoding=UTF-8', '-Djava.net.preferIPv4Stack=true', '-jar', $jar.FullName)
  try { & "$env:JAVA_HOME\bin\java.exe" @jvmArgs @extraArgs }
  finally { Pop-Location }
}

if ($Name -ne 'caddy') {
  $env:JAVA_HOME = Find-Jdk25
  if (-not $env:GRADLE_USER_HOME -or $env:GRADLE_USER_HOME -match 'cursor-sandbox') {
    $env:GRADLE_USER_HOME = "$env:USERPROFILE\.gradle"
  }
}

switch ($Name) {
  'caddy' {
    $caddy = (Get-Command caddy -ErrorAction SilentlyContinue).Source
    if (-not $caddy) {
      $caddy = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter caddy.exe -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    }
    Push-Location $here
    try { & $caddy run --config Caddyfile --adapter caddyfile }
    finally { Pop-Location }
  }
  'cas' {
    Import-DotEnv "$root\cas\.env"
    $env:SPRING_PROFILES_ACTIVE = 'standalone,local'
    Push-Location "$root\cas"
    try { & .\gradlew.bat bootRun --console=plain }
    finally { Pop-Location }
  }
  'klaw' {
    Import-DotEnv "$alpos\klaw\.env"
    Start-AlposJar 'klaw' @()
  }
  'sys' {
    Import-DotEnv "$here\alpos.env"
    Start-AlposJar 'sys' @('--server.http.port=0')
  }
  'oms' {
    Import-DotEnv "$here\alpos.env"
    Start-AlposJar 'oms' @()
  }
}
