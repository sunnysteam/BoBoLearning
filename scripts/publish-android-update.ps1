[CmdletBinding()]
param(
    [string]$ApiBaseUrl = "https://wx.jiayuntong.com:5172/server/",

    [string[]]$ReleaseNote = @("优化体验并提升稳定性"),

    [switch]$AllowInsecureHttp,

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

function Assert-PathInsideDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $resolvedDirectory = [System.IO.Path]::GetFullPath($Directory).TrimEnd('\') + '\'
    if (-not $resolvedPath.StartsWith($resolvedDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "发布目标超出升级包目录：$resolvedPath"
    }
}

$apiUri = $null
if (-not [System.Uri]::TryCreate($ApiBaseUrl, [System.UriKind]::Absolute, [ref]$apiUri)) {
    throw "ApiBaseUrl 必须是包含协议和主机的完整地址"
}
if ($apiUri.Scheme -notin @("http", "https") -or [string]::IsNullOrWhiteSpace($apiUri.Host)) {
    throw "ApiBaseUrl 只允许使用 HTTP 或 HTTPS"
}
if ($apiUri.Scheme -ne "https" -and -not $AllowInsecureHttp) {
    throw "正式升级必须使用 HTTPS；仅本地验收时可显式添加 -AllowInsecureHttp"
}
if ($ReleaseNote.Count -eq 0 -or $ReleaseNote.Count -gt 20) {
    throw "ReleaseNote 必须包含 1 至 20 条中文更新说明"
}
if ($ReleaseNote | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_.Length -gt 200 }) {
    throw "每条更新说明必须为 1 至 200 个字符"
}

$ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$script:ClientRoot = Join-Path $ProjectRoot "Client"
$updatesRoot = Join-Path $ProjectRoot "Service\updates"
$pubspecPath = Join-Path $script:ClientRoot "pubspec.yaml"
$versionLine = Get-Content -LiteralPath $pubspecPath |
    Where-Object { $_ -match '^version:\s*' } |
    Select-Object -First 1
if ($null -eq $versionLine -or $versionLine -notmatch '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$') {
    throw "Client/pubspec.yaml 的 version 必须采用 x.y.z+构建号格式"
}
$versionName = $Matches[1]
$versionCode = [long]$Matches[2]
$apkFileName = "bobo-learning-$versionName-$versionCode.apk"
$apkTarget = Join-Path $updatesRoot $apkFileName
$apkTemporary = Join-Path $updatesRoot ".$apkFileName.tmp"
$manifestTarget = Join-Path $updatesRoot "latest.json"
$manifestTemporary = Join-Path $updatesRoot ".latest.json.tmp"
Assert-PathInsideDirectory -Path $apkTarget -Directory $updatesRoot
Assert-PathInsideDirectory -Path $apkTemporary -Directory $updatesRoot
Assert-PathInsideDirectory -Path $manifestTarget -Directory $updatesRoot
Assert-PathInsideDirectory -Path $manifestTemporary -Directory $updatesRoot

if (-not $SkipBuild) {
    $flutterCommand = Resolve-FlutterCommand
    Write-Host "正在构建 Android Release APK：$versionName+$versionCode"
    Push-Location $script:ClientRoot
    try {
        & $flutterCommand build apk --release "--dart-define=API_BASE_URL=$ApiBaseUrl"
        if ($LASTEXITCODE -ne 0) {
            throw "Android Release APK 构建失败，退出码：$LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

$sourceApk = Join-Path $script:ClientRoot "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path -LiteralPath $sourceApk -PathType Leaf)) {
    throw "没有找到待发布 APK：$sourceApk"
}
if (-not (Test-Path -LiteralPath $updatesRoot -PathType Container)) {
    throw "升级包目录不存在：$updatesRoot"
}

try {
    Copy-Item -LiteralPath $sourceApk -Destination $apkTemporary -Force
    $packageInfo = Get-Item -LiteralPath $apkTemporary
    $sha256 = (Get-FileHash -LiteralPath $apkTemporary -Algorithm SHA256).Hash.ToLowerInvariant()
    if (Test-Path -LiteralPath $apkTarget -PathType Leaf) {
        $publishedSha256 = (Get-FileHash -LiteralPath $apkTarget -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($publishedSha256 -ne $sha256) {
            throw "版本 $versionName+$versionCode 已发布且 APK 内容不同，请先提升 Client/pubspec.yaml 的版本号"
        }
        Remove-Item -LiteralPath $apkTemporary -Force
    }
    else {
        [System.IO.File]::Move($apkTemporary, $apkTarget)
    }

    $manifest = [ordered]@{
        versionName = $versionName
        versionCode = $versionCode
        apkFile = $apkFileName
        sha256 = $sha256
        sizeBytes = $packageInfo.Length
        releaseNotes = @($ReleaseNote)
        publishedAt = [DateTimeOffset]::UtcNow.ToString("o")
    }
    $json = $manifest | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText(
        $manifestTemporary,
        $json + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::Move($manifestTemporary, $manifestTarget, $true)
}
finally {
    if (Test-Path -LiteralPath $apkTemporary) {
        Remove-Item -LiteralPath $apkTemporary -Force
    }
    if (Test-Path -LiteralPath $manifestTemporary) {
        Remove-Item -LiteralPath $manifestTemporary -Force
    }
}

Write-Host "升级包发布完成：$apkFileName"
Write-Host "版本：$versionName+$versionCode"
Write-Host "长度：$($packageInfo.Length) 字节"
Write-Host "SHA-256：$sha256"
Write-Warning "正式发布前必须将 Android Release 从调试签名切换为受保护的固定签名，并妥善备份密钥。"
