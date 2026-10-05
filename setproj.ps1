# OMS 本機補齊腳本。給「alpos 裡已經有一部分專案」的情況用。
#
# 原本的做法（前輩指令）：
#   1. git clone alpos
#   2. alpos\shell-tool\powershell\setproj.ps1 OMS
#        在「目前目錄」clone。目錄已存在就略過，不會覆蓋。
#        若在 alpos 外面執行，會在旁邊再 clone 一份。
#   3. alpos\shell-tool\powershell\gitCheckout.ps1  輸入 springboot3
#   4. 再執行一次 gitCheckout.ps1，輸入 springboot3_IT-10184
#        它會遞迴切換 alpos 底下每一個 .git，包含 alpos 自己，以及 OMS 以外的專案。
#
# 這份腳本：
#   - 一律 clone 到這個檔案旁邊的 ..\alpos
#   - 已有的 git 倉庫只略過，不刪除、不 reset、不強制切換
#   - 目錄在但不是 git 倉庫時略過並警告
#   - 預設只補 clone。加 -Checkout 才切分支，而且只處理下面的 OMS 清單
#   - 工作區有未提交變更時不切換
#   - 遠端沒有該分支時略過，留在原本的分支
#
# 分支順序：先 springboot3，遠端有 springboot3_IT-10184 再切過去。
# 開 MR：springboot3_IT-10184 => springboot3
# 參考：https://allylogisticproperty.atlassian.net/browse/IT-10694
#
# 用法：
#   .\setproj.ps1                 只補齊缺少的 OMS 專案
#   .\setproj.ps1 -DryRun         只列出會 clone / 會略過的項目
#   .\setproj.ps1 -Checkout       補齊後，依上面的順序切分支
#   .\setproj.ps1 -Checkout -DryRun

param(
    [switch]$Checkout,
    [switch]$DryRun,
    [string]$BaseBranch = 'springboot3',
    [string]$FeatureBranch = 'springboot3_IT-10184'
)

$ErrorActionPreference = 'Continue'

# 與 alpos\shell-tool\powershell\setproj.ps1 的 $OMS_DEPS 相同
$OmsProjects = @(
    'boss', 'guts', 'hulk', 'loki', 'oms', 'magneto', 'redhulk', 'thor', 'yaps',
    'ink', 'kiss',
    'ares', 'arms', 'dos', 'google-lib', 'kafka-lib', 'mars', 'morph', 'plus', 'wanda', 'zeus',
    'activiti-lib', 'websocket-lib', 'sync-data-lib', 'microsoft-lib', 'clean-lib'
)

$AlposRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\alpos')).Path

function Clone-Missing {
    $cloned = @()
    $skipped = @()
    $failed = @()

    Write-Host "OMS projects: $($OmsProjects.Count)" -ForegroundColor Cyan
    Write-Host "Clone into:  $AlposRoot" -ForegroundColor Cyan
    Write-Host ''

    foreach ($proj in $OmsProjects) {
        $dir = Join-Path $AlposRoot $proj
        if (Test-Path (Join-Path $dir '.git')) {
            $branch = (& git -C $dir rev-parse --abbrev-ref HEAD 2>$null)
            Write-Host "[SKIP] $proj already exists ($branch)" -ForegroundColor Green
            $skipped += $proj
            continue
        }
        if (Test-Path $dir) {
            Write-Host "[SKIP] $proj exists but is not a git repo. Not touching it." -ForegroundColor Yellow
            $skipped += $proj
            continue
        }
        if ($DryRun) {
            Write-Host "[DRY]  would clone $proj" -ForegroundColor Cyan
            $cloned += $proj
            continue
        }
        Write-Host "[CLONE] $proj" -ForegroundColor Cyan
        & git clone "https://git.alp.com.tw/alp/${proj}.git" $dir
        if ($LASTEXITCODE -eq 0) {
            $cloned += $proj
        }
        else {
            Write-Host "[FAILED] $proj" -ForegroundColor Red
            $failed += $proj
        }
    }

    Write-Host ''
    Write-Host "Clone summary: new=$($cloned.Count) skipped=$($skipped.Count) failed=$($failed.Count)" -ForegroundColor Cyan
    return $failed.Count -eq 0
}

function Switch-RepoBranch {
    param([string]$Repo, [string]$Branch)

    $name = Split-Path $Repo -Leaf
    $dirty = & git -C $Repo status --porcelain
    if ($dirty) {
        Write-Host "[DIRTY] $name has uncommitted changes. Left as-is." -ForegroundColor Yellow
        return 'dirty'
    }

    $current = (& git -C $Repo rev-parse --abbrev-ref HEAD 2>$null).Trim()
    & git -C $Repo fetch origin $Branch --quiet 2>$null | Out-Null
    $remote = & git -C $Repo branch -r --list "origin/$Branch"
    if (-not $remote) {
        Write-Host "[SKIP] $name has no origin/$Branch (stays on $current)" -ForegroundColor Yellow
        return 'missing'
    }
    if ($current -eq $Branch) {
        Write-Host "[OK] $name already on $Branch" -ForegroundColor Green
        return 'ok'
    }
    if ($DryRun) {
        Write-Host "[DRY]  $name $current -> $Branch" -ForegroundColor Cyan
        return 'ok'
    }

    & git -C $Repo checkout $Branch 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        & git -C $Repo checkout -B $Branch "origin/$Branch" 2>&1 | Out-Null
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] $name -> $Branch" -ForegroundColor Green
        return 'ok'
    }
    Write-Host "[FAILED] $name could not checkout $Branch" -ForegroundColor Red
    return 'failed'
}

function Switch-OmsBranches {
    Write-Host ''
    Write-Host "Checkout: $BaseBranch, then $FeatureBranch when the remote has it" -ForegroundColor Cyan
    Write-Host "MR later: $FeatureBranch => $BaseBranch" -ForegroundColor Cyan
    Write-Host 'Reference: https://allylogisticproperty.atlassian.net/browse/IT-10694' -ForegroundColor Cyan
    Write-Host ''

    foreach ($proj in $OmsProjects) {
        $dir = Join-Path $AlposRoot $proj
        if (-not (Test-Path (Join-Path $dir '.git'))) { continue }

        $base = Switch-RepoBranch -Repo $dir -Branch $BaseBranch
        if ($base -eq 'dirty' -or $base -eq 'failed') { continue }
        if ($base -eq 'missing') { continue }

        Switch-RepoBranch -Repo $dir -Branch $FeatureBranch | Out-Null
    }
}

Write-Host 'local-dev setproj (OMS only)' -ForegroundColor Green
if (-not (Clone-Missing)) {
    Write-Host 'Some clones failed. Checkout was not started.' -ForegroundColor Red
    exit 1
}
if ($Checkout) {
    Switch-OmsBranches
}
else {
    Write-Host ''
    Write-Host 'Clone step only. Existing repos were not switched.' -ForegroundColor Yellow
    Write-Host "They are still on their current branch (many are springboot3-master, not $BaseBranch)." -ForegroundColor Yellow
    Write-Host "Run again with -Checkout to move OMS repos to $BaseBranch, then $FeatureBranch." -ForegroundColor Yellow
    Write-Host "MR: $FeatureBranch => $BaseBranch" -ForegroundColor Yellow
}
