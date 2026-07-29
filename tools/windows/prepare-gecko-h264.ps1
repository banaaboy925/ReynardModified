[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$SourceRoot = (Get-Location).Path,

    [switch]$ResetFirefox
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$GitArgs)

    & git @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "git failed with exit code ${LASTEXITCODE}: git $($GitArgs -join ' ')"
    }
}

$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$releaseFile = Join-Path $SourceRoot 'engine\release.txt'
$patchRoot = Join-Path $SourceRoot 'patches'
$firefoxDir = Join-Path $SourceRoot 'engine\firefox'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git for Windows is required.'
}
if (-not (Test-Path -LiteralPath $releaseFile -PathType Leaf)) {
    throw "Not a Reynard source folder: missing $releaseFile"
}
if (-not (Test-Path -LiteralPath $patchRoot -PathType Container)) {
    throw "Missing patch folder: $patchRoot"
}

$releaseTag = (Get-Content -LiteralPath $releaseFile -Raw).Trim()
if ($releaseTag -ne 'FIREFOX_153_0_RELEASE') {
    throw "This package expects FIREFOX_153_0_RELEASE, found '$releaseTag'."
}

$firefoxGit = Join-Path $firefoxDir '.git'
if ($ResetFirefox -and (Test-Path -LiteralPath $firefoxDir)) {
    Remove-Item -LiteralPath $firefoxDir -Recurse -Force
}

if (-not (Test-Path -LiteralPath $firefoxGit)) {
    if (Test-Path -LiteralPath $firefoxDir) {
        $items = @(Get-ChildItem -LiteralPath $firefoxDir -Force)
        if ($items.Count -gt 0) {
            throw "engine\firefox exists but is not a Git checkout. Remove it or rerun with -ResetFirefox."
        }
        Remove-Item -LiteralPath $firefoxDir -Recurse -Force
    }

    Write-Host 'Cloning the Firefox repository metadata...'
    Invoke-Git -GitArgs @(
        'clone',
        '--filter=blob:none',
        '--no-checkout',
        'https://github.com/mozilla-firefox/firefox',
        $firefoxDir
    )
}

$status = (& git -C $firefoxDir status --porcelain)
if ($LASTEXITCODE -ne 0) {
    throw 'Could not inspect the Firefox checkout.'
}
if ($status -and -not $ResetFirefox) {
    throw 'engine\firefox has local changes. Rerun with -ResetFirefox to discard them.'
}

Write-Host "Fetching $releaseTag..."
Invoke-Git -GitArgs @(
    '-C', $firefoxDir,
    'fetch', '--force', '--depth', '1', 'origin',
    "refs/tags/${releaseTag}:refs/tags/${releaseTag}"
)
Invoke-Git -GitArgs @('-C', $firefoxDir, 'checkout', '--detach', "refs/tags/${releaseTag}")
Invoke-Git -GitArgs @('-C', $firefoxDir, 'reset', '--hard', "refs/tags/${releaseTag}")
Invoke-Git -GitArgs @('-C', $firefoxDir, 'clean', '-fdx')

$patches = @(Get-ChildItem -LiteralPath $patchRoot -Recurse -File -Filter '*.patch' |
    Sort-Object FullName)
if ($patches.Count -eq 0) {
    throw 'No patch files were found.'
}

foreach ($patch in $patches) {
    $relative = $patch.FullName.Substring($patchRoot.Length).TrimStart('\', '/')
    $patchPath = $patch.FullName.Replace('\', '/')

    Write-Host "Checking $relative"
    Invoke-Git -GitArgs @(
        '-C', $firefoxDir,
        'apply', '--check', '--whitespace=nowarn', $patchPath
    )

    Write-Host "Applying $relative"
    Invoke-Git -GitArgs @(
        '-C', $firefoxDir,
        'apply', '--whitespace=nowarn', $patchPath
    )
}

$prefs = Join-Path $firefoxDir 'modules\libpref\init\StaticPrefList.yaml'
$defaultPrefs = Join-Path $firefoxDir 'dom\media\webrtc\jsapi\DefaultCodecPreferences.cpp'
$jsep = Join-Path $firefoxDir 'dom\media\webrtc\jsep\JsepCodecDescription.h'

$checks = @(
    @{ Path = $prefs; Pattern = '#if defined\(MOZ_WIDGET_ANDROID\) \|\| defined\(XP_IOS\)' },
    @{ Path = $prefs; Pattern = '#if defined\(ANDROID\) \|\| defined\(XP_IOS\)' },
    @{ Path = $defaultPrefs; Pattern = 'ReceivingH264SupportedStatic' },
    @{ Path = $defaultPrefs; Pattern = 'MediaDataCodec::SupportsDecoderCodec' },
    @{ Path = $jsep; Pattern = 'SendingH264Supported' }
)
foreach ($check in $checks) {
    if (-not (Select-String -LiteralPath $check.Path -Pattern $check.Pattern -Quiet)) {
        throw "Verification failed for $($check.Path): $($check.Pattern)"
    }
}

Write-Host ''
Write-Host 'Success: Firefox 153 is checked out and all Reynard/H.264 patches are applied.' -ForegroundColor Green
Write-Host 'Important: the iOS build itself still requires macOS/Xcode or GitHub Actions.'
Write-Host ''
Write-Host 'Changed WebRTC files:'
Invoke-Git -GitArgs @('-C', $firefoxDir, 'diff', '--stat')
