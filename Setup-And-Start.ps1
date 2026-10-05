# 給同事的第一次／之後啟動。
# 缺少的軟體、憑證、程式碼會補上；都齊了就直接執行 Start-ImitationDev.cmd。
# Nexus 帳號只問一次，寫進這台電腦的 %USERPROFILE%\.gradle\gradle.properties，不會進 Git。
# Docker 若是這次才安裝，或 Windows 還沒有 WSL，需要重新開機後再雙擊一次。

$ErrorActionPreference = 'Continue'
Write-Host 'setup script started'
$Here = $PSScriptRoot
$Root = (Resolve-Path (Join-Path $Here '..')).Path

function Stop-Setup([int]$Code) {
    Write-Host ''
    Read-Host '按 Enter 關閉這個視窗'
    exit $Code
}

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal $id
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-Jdk25 {
    $candidates = @()
    foreach ($scope in @('Process', 'User', 'Machine')) {
        $home = [Environment]::GetEnvironmentVariable('JAVA_HOME', $scope)
        if ($home) { $candidates += $home }
    }
    foreach ($base in @(
            'C:\Program Files\Zulu',
            'C:\Program Files\Java',
            'C:\Program Files\Eclipse Adoptium',
            'C:\Program Files\Microsoft'
        )) {
        if (Test-Path $base) {
            $candidates += @(Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        }
    }
    foreach ($dir in ($candidates | Select-Object -Unique)) {
        $release = Join-Path $dir 'release'
        if ((Test-Path $release) -and (Select-String -Path $release -Pattern 'JAVA_VERSION="25' -Quiet)) {
            return $dir
        }
    }
    return $null
}

function Find-Caddy {
    $cmd = Get-Command caddy -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $hit = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter caddy.exe -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return $null
}

function Test-Node24 {
    $cmd = Get-Command node -ErrorAction SilentlyContinue
    if (-not $cmd) { return $false }
    $raw = (& node -v) -replace 'v', ''
    $major = [int]($raw.Split('.')[0])
    return $major -ge 24
}

function Test-DockerEngine {
    $cmd = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $cmd) { return $false }
    $version = & docker version --format '{{.Server.Version}}' 2>$null
    return [bool]$version
}

function Test-NexusConfig {
    $path = Join-Path $env:USERPROFILE '.gradle\gradle.properties'
    if (-not (Test-Path $path)) { return $false }
    $text = [IO.File]::ReadAllText($path)
    return ($text -match '(?m)^systemProp\.nexus\.username=\S') -and
           ($text -match '(?m)^systemProp\.nexus\.password=\S') -and
           ($text -match '(?m)^systemProp\.nexus\.group\.url=\S')
}

function Install-Winget([string]$Id) {
    Write-Host "安裝 $Id ..."
    & winget install --id $Id -e --disable-interactivity --accept-package-agreements --accept-source-agreements
    return ($LASTEXITCODE -eq 0)
}

Refresh-Path
Write-Host ''
Write-Host '檢查本機開發環境' -ForegroundColor Cyan

$jdk = Find-Jdk25
$needJdk = -not $jdk
$needNode = -not (Test-Node24)
$needCaddy = -not (Find-Caddy)
$needMemurai = -not (Get-Service Memurai -ErrorAction SilentlyContinue)
$needDocker = -not (Get-Command docker -ErrorAction SilentlyContinue)
$missingSoftware = $needJdk -or $needNode -or $needCaddy -or $needMemurai -or $needDocker

if ($missingSoftware -and -not (Test-Admin)) {
    Write-Host '有軟體還沒安裝，需要系統管理員權限。' -ForegroundColor Yellow
    Write-Host '請看工作列有沒有跳出「你要允許此應用程式對您的裝置進行變更嗎」，按「是」。' -ForegroundColor Yellow
    Write-Host '真正在安裝的是後面那扇視窗，不是這扇。' -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Stop-Setup 0
}

if ($needJdk) { Install-Winget 'Azul.Zulu.25.JDK' | Out-Null }
if ($needNode) { Install-Winget 'OpenJS.NodeJS.LTS' | Out-Null }
if ($needCaddy) { Install-Winget 'CaddyServer.Caddy' | Out-Null }
if ($needMemurai) { Install-Winget 'Memurai.MemuraiDeveloper' | Out-Null }
if ($needDocker) { Install-Winget 'Docker.DockerDesktop' | Out-Null }
Refresh-Path

$jdk = Find-Jdk25
if (-not $jdk) {
    Write-Host '找不到 JDK 25。請安裝 Azul Zulu 25，把 JAVA_HOME 指過去，然後再雙擊一次。' -ForegroundColor Red
    Stop-Setup 1
}
$env:JAVA_HOME = $jdk
[Environment]::SetEnvironmentVariable('JAVA_HOME', $jdk, 'User')
Write-Host "JDK 25: $jdk"

$crt = Join-Path $Here 'certs\mycas.crt'
$keytool = Join-Path $jdk 'bin\keytool.exe'
if ((Test-Path $crt) -and (Test-Path $keytool)) {
    & $keytool -list -alias mycas -cacerts -storepass changeit 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host '把 mycas 憑證匯入 JDK 25 ...'
        & $keytool -importcert -noprompt -alias mycas -cacerts -file $crt -storepass changeit
        if ($LASTEXITCODE -ne 0) {
            Write-Host '憑證沒匯入成功。請用系統管理員再雙擊一次。' -ForegroundColor Red
            Stop-Setup 1
        }
    }
    else {
        Write-Host 'JDK 已信任 mycas'
    }
}

if (-not (Test-NexusConfig)) {
    Write-Host ''
    Write-Host '這台電腦還沒有 Nexus 設定。帳號只會存在你的使用者目錄，不會寫進專案。' -ForegroundColor Yellow
    $userName = Read-Host 'Nexus username'
    $secure = Read-Host 'Nexus password' -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    $gradleDir = Join-Path $env:USERPROFILE '.gradle'
    New-Item -ItemType Directory -Force -Path $gradleDir | Out-Null
    $props = Join-Path $gradleDir 'gradle.properties'
    $block = @"
systemProp.nexus.group.url=https://nexus.alp.com.tw/repository/alp-public/
systemProp.nexus.username=$userName
systemProp.nexus.password=$password

"@
    [IO.File]::AppendAllText($props, $block)
    Write-Host 'Nexus 設定已寫入。'
}

function Ensure-Repo([string]$Name, [string]$Url, [string]$Branch) {
    $dir = Join-Path $Root $Name
    if (Test-Path (Join-Path $dir '.git')) {
        Write-Host "已有 $Name"
        return
    }
    Write-Host "抓取 $Name ..."
    if ($Branch) { & git clone -b $Branch $Url $dir }
    else { & git clone $Url $dir }
    if ($LASTEXITCODE -ne 0) { throw "clone $Name failed" }
}

try {
    Ensure-Repo 'alpos' 'https://git.alp.com.tw/alp/alpos.git' 'springboot3'
    Ensure-Repo 'webapp' 'https://git.alp.com.tw/alp/webapp.git' ''
    Ensure-Repo 'imitation-cas' 'https://git.alp.com.tw/alp/imitation-cas.git' ''
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host '程式碼沒抓下來。請確認看得到 git.alp.com.tw（公司內網或 VPN），然後再雙擊一次。' -ForegroundColor Red
    Stop-Setup 1
}

Write-Host '補齊 alpos 裡缺少的 OMS 專案（已有的會略過）...'
$copiedSetproj = Join-Path $env:TEMP 'alp-setproj.ps1'
[IO.File]::WriteAllText($copiedSetproj, [IO.File]::ReadAllText("$Here\setproj.ps1"))
& powershell.exe -NoProfile -File $copiedSetproj
if ($LASTEXITCODE -ne 0) { Stop-Setup 1 }

$webapp = Join-Path $Root 'webapp'
if (-not (Test-Path (Join-Path $webapp 'node_modules'))) {
    if (-not (Test-Node24)) {
        Write-Host 'Node.js 24 還沒進到這個視窗的 PATH。請關掉視窗，再雙擊一次。' -ForegroundColor Yellow
        Stop-Setup 1
    }
    Write-Host 'webapp npm install ...'
    Push-Location $webapp
    & npm install
    $npmCode = $LASTEXITCODE
    Pop-Location
    if ($npmCode -ne 0) {
        Write-Host 'npm install 失敗。' -ForegroundColor Red
        Stop-Setup 1
    }
}

$wsl = Join-Path $env:SystemRoot 'System32\wsl.exe'
if (-not (Test-DockerEngine)) {
    & $wsl --status 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Windows 還沒有 WSL，Docker 無法啟動。正在安裝，完成後請重新開機，再開 Docker Desktop，然後再雙擊一次。' -ForegroundColor Yellow
        & $wsl --install --no-distribution
        Stop-Setup 1
    }
    Write-Host 'Docker 引擎還沒在跑。請打開 Docker Desktop，等它顯示 Engine running，然後再雙擊一次。' -ForegroundColor Yellow
    Stop-Setup 1
}

if (-not (Get-Service Memurai -ErrorAction SilentlyContinue)) {
    Write-Host 'Memurai 還沒裝好。請用系統管理員再雙擊一次。' -ForegroundColor Red
    Stop-Setup 1
}
if (-not (Find-Caddy)) {
    Write-Host '找不到 Caddy。請關掉視窗再雙擊一次，讓 PATH 更新。' -ForegroundColor Yellow
    Stop-Setup 1
}
if (-not (Test-Node24)) {
    Write-Host '找不到 Node.js 24。請關掉視窗再雙擊一次。' -ForegroundColor Yellow
    Stop-Setup 1
}

Write-Host ''
Write-Host '環境已齊，開始啟動。' -ForegroundColor Green
Start-Process -FilePath "$env:ComSpec" -WorkingDirectory $Here -ArgumentList '/c', 'Start-ImitationDev.cmd'
Stop-Setup 0
