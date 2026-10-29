#Requires -Version 5.1
<#
.SYNOPSIS
    采集手表版的运行状态与日志，用于确认「能启动」并排查崩溃。

.DESCRIPTION
    比 screenshot.ps1 更偏诊断：启动 App，等一会儿，然后检查进程是否还活着、
    Activity 是否处于 resumed 状态，并把 logcat（含崩溃栈）导出到文件。
    装不上或一打开就闪退时先跑这个。

.EXAMPLE
    .\scripts\diagnose.ps1
    .\scripts\diagnose.ps1 -SettleSeconds 20
#>
[CmdletBinding()]
param(
    [string]$AndroidHome = 'D:\android-build\sdk',
    [string]$OutDir,
    [int]$SettleSeconds = 12,
    [string]$Serial
)

$ErrorActionPreference = 'Stop'
$androidDir = Split-Path -Parent $PSScriptRoot
$package = 'com.agentsanywhere.app.watch'
$activity = "$package/.watch.WatchMainActivity"

if (-not $OutDir) { $OutDir = Join-Path $androidDir 'watch\diagnostics' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

$adb = Join-Path $AndroidHome 'platform-tools\adb.exe'
if (-not (Test-Path $adb)) { throw "找不到 adb：$adb" }

$adbArgs = @()
if ($Serial) { $adbArgs += @('-s', $Serial) }

$connected = & $adb @adbArgs devices | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice$' }
if (-not $connected) {
    throw '没有检测到已授权的手表。请先用手表设置里的「USB 调试」连接，然后接受调试授权。'
}

function Invoke-Adb {
    param([string[]]$Arguments)
    return (& $adb @adbArgs @Arguments 2>&1) -join "`n"
}

Write-Host '=== 设备 ==='
$model = (Invoke-Adb @('shell', 'getprop', 'ro.product.model')).Trim()
$sdk = (Invoke-Adb @('shell', 'getprop', 'ro.build.version.sdk')).Trim()
$release = (Invoke-Adb @('shell', 'getprop', 'ro.build.version.release')).Trim()
Write-Host "型号      : $model"
Write-Host "Android   : $release (API $sdk)"
Write-Host "wm size   : $((Invoke-Adb @('shell','wm','size')).Trim())"
Write-Host "wm density: $((Invoke-Adb @('shell','wm','density')).Trim())"

Write-Host '=== 安装状态 ==='
$installed = Invoke-Adb @('shell', 'pm', 'path', $package)
if ($installed -match 'package:') {
    Write-Host $installed.Trim()
    $dump = Invoke-Adb @('shell', 'dumpsys', 'package', $package)
    ($dump -split "`n" | Where-Object { $_ -match 'versionName=|versionCode=|firstInstallTime=|lastUpdateTime=|minSdk=|targetSdk=' }) |
        ForEach-Object { Write-Host ("  " + $_.Trim()) }
} else {
    Write-Warning "手表上没有安装 $package，请先跑 build-and-install.ps1。"
    return
}

Write-Host '=== 启动并观察 ==='
Invoke-Adb @('logcat', '-c') | Out-Null
Invoke-Adb @('shell', 'am', 'start', '-W', '-n', $activity) | ForEach-Object { Write-Host $_ }
Start-Sleep -Seconds $SettleSeconds

$pidText = (Invoke-Adb @('shell', 'pidof', $package)).Trim()
if ([string]::IsNullOrWhiteSpace($pidText)) {
    Write-Warning "进程不存在：App 启动后退出或崩溃了。看下面的日志。"
} else {
    Write-Host "进程存活  : pid=$pidText"
}

$resumed = Invoke-Adb @('shell', 'dumpsys', 'activity', 'activities')
$activityLines = $resumed -split "`n" | Where-Object { $_ -match [regex]::Escape($package) }
if ($activityLines) {
    Write-Host '相关 Activity 状态：'
    $activityLines | Select-Object -First 8 | ForEach-Object { Write-Host ("  " + $_.Trim()) }
}

Write-Host '=== 导出日志 ==='
$fullLog = Join-Path $OutDir "logcat-$stamp.txt"
$crashLog = Join-Path $OutDir "crash-$stamp.txt"
Invoke-Adb @('logcat', '-d', '-v', 'threadtime') | Set-Content -Path $fullLog -Encoding UTF8

$lines = Get-Content $fullLog
$interesting = $lines | Where-Object {
    $_ -match 'AndroidRuntime|FATAL EXCEPTION|ANR in|beginning of crash|ActivityManager.*(crash|died)|Fatal signal'
}
$appLines = $lines | Where-Object { $_ -match [regex]::Escape($package) }
@(
    "=== 崩溃 / ANR 相关 ==="
    $interesting
    ""
    "=== 本应用相关 ==="
    $appLines
) | Set-Content -Path $crashLog -Encoding UTF8

if ($interesting) {
    Write-Warning "发现崩溃或 ANR 迹象，见 $crashLog"
    $interesting | Select-Object -First 40 | ForEach-Object { Write-Host $_ }
} else {
    Write-Host '日志里没有崩溃 / ANR 记录。'
}

Write-Host ''
Write-Host "完整日志: $fullLog"
Write-Host "过滤日志: $crashLog"
