[CmdletBinding()]
param(
    [string]$ApiBaseUrl = "https://wx.jiayuntong.com:5172/server/",

    [string]$BuildTimestamp = (Get-Date -Format "yyyyMMddHHmmss"),

    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-FlutterCommand {
    $flutter = Get-Command flutter -ErrorAction SilentlyContinue
    if ($null -ne $flutter) {
        return $flutter.Source
    }

    $propertiesPath = Join-Path $script:ClientRoot "android\local.properties"
    if (Test-Path -LiteralPath $propertiesPath) {
        $sdkLine = Get-Content -LiteralPath $propertiesPath |
            Where-Object { $_ -match '^flutter\.sdk=' } |
            Select-Object -First 1
        if ($null -ne $sdkLine) {
            $sdkPath = ($sdkLine -replace '^flutter\.sdk=', '') -replace '\\:', ':' -replace '\\\\', '\'
            $candidate = Join-Path $sdkPath "bin\flutter.bat"
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }

    throw "未找到 Flutter，请先配置 PATH 或 Client/android/local.properties"
}

if ($BuildTimestamp -notmatch '^\d{14}$') {
    throw "BuildTimestamp 必须是 yyyyMMddHHmmss 格式的 14 位数字"
}

$ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$script:ClientRoot = Join-Path $ProjectRoot "Client"
$flutterCommand = Resolve-FlutterCommand
$flutterBin = Split-Path -Parent $flutterCommand
$dartCommand = Join-Path $flutterBin "cache\dart-sdk\bin\dart.exe"
if (-not (Test-Path -LiteralPath $dartCommand -PathType Leaf)) {
    throw "未找到 Flutter 随附的 Dart：$dartCommand"
}

if (-not $SkipBuild) {
    Write-Host "正在构建 Flutter Web Release：$BuildTimestamp"
    Push-Location $script:ClientRoot
    try {
        & $flutterCommand build web --release --base-href=/ "--dart-define=API_BASE_URL=$ApiBaseUrl"
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter Web Release 构建失败，退出码：$LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

$buildDirectory = Join-Path $script:ClientRoot "build\web"
$stampScript = Join-Path $PSScriptRoot "stamp-web-build.dart"
& $dartCommand $stampScript $buildDirectory $BuildTimestamp
if ($LASTEXITCODE -ne 0) {
    throw "Web 构建时间戳写入失败，退出码：$LASTEXITCODE"
}

Write-Host "Flutter Web Release 构建完成：$BuildTimestamp"
