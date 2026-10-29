#Requires -Version 5.1
<#
.SYNOPSIS
    构建 Agents Anywhere 手表版 APK，并可选安装到通过 USB 连接的手表。

.EXAMPLE
    .\scripts\build-and-install.ps1
    .\scripts\build-and-install.ps1 -Variant Release
    .\scripts\build-and-install.ps1 -SkipInstall
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Variant = 'Debug',

    # 默认值与本机已验证的环境一致，可用参数覆盖。
    [string]$JdkHome = 'D:\android-build\jdk17\jdk-17.0.20.1+1',
    [string]$AndroidHome = 'D:\android-build\sdk',
    [string]$GradleUserHome = 'D:\android-build\gradle-home',

    [switch]$SkipInstall,
    [string]$Serial
)

$ErrorActionPreference = 'Stop'
$androidDir = Split-Path -Parent $PSScriptRoot

function Resolve-JdkHome {
    param([string]$Preferred)
    if ($Preferred -and (Test-Path (Join-Path $Preferred 'bin\java.exe'))) { return $Preferred }
    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) { return $env:JAVA_HOME }
    throw '找不到 JDK 17，请用 -JdkHome 指定，或设置 JAVA_HOME。'
}

$jdk = Resolve-JdkHome -Preferred $JdkHome
if (-not (Test-Path $AndroidHome)) { throw "找不到 Android SDK：$AndroidHome" }

$env:JAVA_HOME = $jdk
$env:ANDROID_HOME = $AndroidHome
$env:ANDROID_SDK_ROOT = $AndroidHome
if ($GradleUserHome -and (Test-Path $GradleUserHome)) { $env:GRADLE_USER_HOME = $GradleUserHome }
$env:PATH = "$jdk\bin;$AndroidHome\platform-tools;$env:PATH"

Write-Host "JDK        : $jdk"
Write-Host "SDK        : $AndroidHome"
Write-Host "Gradle home: $env:GRADLE_USER_HOME"

$task = ":watch:assemble$Variant"
Write-Host "构建 $task ..."
Push-Location $androidDir
try {
    & (Join-Path $androidDir 'gradlew.bat') $task --console=plain
    if ($LASTEXITCODE -ne 0) { throw "Gradle 构建失败（exit $LASTEXITCODE）" }
} finally {
    Pop-Location
}

$flavor = $Variant.ToLowerInvariant()
$apk = Join-Path $androidDir "watch\build\outputs\apk\$flavor\watch-$flavor.apk"
if (-not (Test-Path $apk)) { throw "构建成功但找不到产物：$apk" }
$apkItem = Get-Item $apk
Write-Host ("APK        : {0} ({1:N0} bytes)" -f $apkItem.FullName, $apkItem.Length)

if ($SkipInstall) {
    Write-Host '已跳过安装（-SkipInstall）。'
    return
}

$adb = Join-Path $AndroidHome 'platform-tools\adb.exe'
if (-not (Test-Path $adb)) { throw "找不到 adb：$adb" }

$adbArgs = @()
if ($Serial) { $adbArgs += @('-s', $Serial) }

$connected = & $adb @adbArgs devices | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice$' }
if (-not $connected) {
    throw @'
没有检测到已授权的手表。
  1) 手表：设置 → 关于 → 连点版本号 7 次，打开开发者模式
  2) 手表：设置 → 开发者选项 → 打开「USB 调试」
  3) 用充电线把手表接到电脑（OPPO 手表通常不支持无线 ADB）
  4) 手表上允许这台电脑调试，然后重新运行本脚本
'@
}

Write-Host "安装到手表 ..."
& $adb @adbArgs install -r $apk
if ($LASTEXITCODE -ne 0) { throw 'adb install 失败。' }

& $adb @adbArgs shell am start -n 'com.agentsanywhere.app.watch/.watch.WatchMainActivity' | Out-Null
Write-Host '安装完成并已启动：Agents Anywhere 手表版'
