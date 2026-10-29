#Requires -Version 5.1
<#
.SYNOPSIS
    抓取手表版四个界面的截图，并记录屏幕尺寸 / 密度等实测参数。

.DESCRIPTION
    依赖 build-and-install.ps1 已经把手表版装好并授权 adb。
    截图的页面顺序与 WatchShell.kt 里的 WatchPageOrder 一致：
        [0] 侧栏   [1] 对话(启动页)   [2] 操作   [3] 账号
    即：手指往右拖 → 侧栏，手指往左拖 → 操作 → 账号。
    如果你改过 WatchPageOrder，请同步修改下面的翻页序列。

.EXAMPLE
    .\scripts\screenshot.ps1
    .\scripts\screenshot.ps1 -SettleSeconds 10
#>
[CmdletBinding()]
param(
    [string]$AndroidHome = 'D:\android-build\sdk',
    [string]$OutDir,
    [int]$SettleSeconds = 6,
    [string]$Serial
)

$ErrorActionPreference = 'Stop'
$androidDir = Split-Path -Parent $PSScriptRoot

if (-not $OutDir) { $OutDir = Join-Path $androidDir 'watch\screenshots' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$adb = Join-Path $AndroidHome 'platform-tools\adb.exe'
if (-not (Test-Path $adb)) { throw "找不到 adb：$adb" }

$adbArgs = @()
if ($Serial) { $adbArgs += @('-s', $Serial) }

$connected = & $adb @adbArgs devices | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice$' }
if (-not $connected) { throw '没有检测到已授权的手表，请先运行 build-and-install.ps1。' }

function Get-Prop {
    param([string]$Key, [string]$Default = 'unknown')
    $value = (& $adb @adbArgs shell getprop $Key) -join ''
    $value = $value.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

# 屏幕尺寸用于按比例算滑动坐标，密度用于核对圆屏安全边距。
$sizeText = (& $adb @adbArgs shell wm size) -join "`n"
$width = 466
$height = 466
if ($sizeText -match '(\d+)x(\d+)') {
    $width = [int]$Matches[1]
    $height = [int]$Matches[2]
}
$densityText = (& $adb @adbArgs shell wm density) -join "`n"
$density = 320
if ($densityText -match '(\d+)') { $density = [int]$Matches[1] }

# 内接正方形推出的横向安全边距（px）：(边长 - 边长/√2)/2
$safeInsetPx = [int](($width - ($width / [Math]::Sqrt(2))) / 2)
$safeInsetDp = [Math]::Round($safeInsetPx * 160 / $density)

$info = @(
    "capturedAt     = $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "model          = $(Get-Prop 'ro.product.model')",
    "androidSdk     = $(Get-Prop 'ro.build.version.sdk')",
    "release        = $(Get-Prop 'ro.build.version.release')",
    "fingerprint    = $(Get-Prop 'ro.build.fingerprint')",
    "wm size        = ${width}x${height}",
    "wm density     = $density",
    "derivedSafeInsetPx = $safeInsetPx",
    "derivedSafeInsetDp = $safeInsetDp",
    "expectedWatchSafeHorizontalDp = $safeInsetDp"
)
$infoPath = Join-Path $OutDir 'device-info.txt'
$info | Set-Content -Path $infoPath -Encoding UTF8
$info | ForEach-Object { Write-Host $_ }

$midY = [int]($height / 2)
$leftX = [int]($width * 0.25)
$rightX = [int]($width * 0.75)

function Invoke-Swipe {
    param([ValidateSet('Next', 'Previous')][string]$Direction)
    # Next = 手指往左划 = 去后一页（index+1）；Previous = 手指往右划 = 去前一页（index-1）
    if ($Direction -eq 'Next') {
        & $adb @adbArgs shell input swipe $rightX $midY $leftX $midY 220 | Out-Null
    } else {
        & $adb @adbArgs shell input swipe $leftX $midY $rightX $midY 220 | Out-Null
    }
    Start-Sleep -Milliseconds 900
}

function Save-Screenshot {
    param([string]$Name)
    $remote = "/sdcard/aa-watch-$Name.png"
    $local = Join-Path $OutDir "$Name.png"
    & $adb @adbArgs shell screencap -p $remote | Out-Null
    & $adb @adbArgs pull $remote $local | Out-Null
    & $adb @adbArgs shell rm -f $remote | Out-Null
    Write-Host ("  {0}.png" -f $Name)
}

Write-Host '启动手表版 ...'
& $adb @adbArgs shell am start -n 'com.agentsanywhere.app.watch/.watch.WatchMainActivity' | Out-Null
Start-Sleep -Seconds $SettleSeconds

# 启动页是 index 1（对话）。手指往右拖到侧栏（index 0），再往左拖依次经过
# 对话(1) → 操作(2) → 账号(3)。
Write-Host '抓取截图 ...'
Save-Screenshot '01-conversation'
Invoke-Swipe -Direction Previous
Save-Screenshot '02-sidebar'
Invoke-Swipe -Direction Next
Invoke-Swipe -Direction Next
Save-Screenshot '03-actions'
Invoke-Swipe -Direction Next
Save-Screenshot '04-account'

Write-Host "完成。截图与 device-info.txt 在：$OutDir"
