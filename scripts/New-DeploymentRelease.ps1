[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Version,

    [string]$AiorsRepo,
    [string]$SvxLinkRepo,
    [string]$MinisignSecretKey,
    [string]$ReleaseRepo = 'S56TS/aiors_deploy',
    [switch]$Rebuild,
    [switch]$CreateDraft
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$deployRoot = Split-Path -Parent $PSScriptRoot

function Find-Repository {
    param(
        [Parameter(Mandatory = $true)][string]$StartPath,
        [Parameter(Mandatory = $true)][string]$RepositoryName
    )

    $cursor = Get-Item -LiteralPath $StartPath
    while ($null -ne $cursor) {
        $candidate = Join-Path $cursor.FullName $RepositoryName
        if (Test-Path -LiteralPath (Join-Path $candidate '.git')) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
        $cursor = $cursor.Parent
    }

    throw "Could not find repository '$RepositoryName'; provide its path explicitly."
}

function Convert-ToWslPath {
    param([Parameter(Mandatory = $true)][string]$WindowsPath)

    $resolved = (Resolve-Path -LiteralPath $WindowsPath).Path
    if ($resolved -notmatch '^([A-Za-z]):\\(.*)$') {
        throw "Only local Windows drive paths can be converted to WSL paths: '$resolved'"
    }
    $drive = $Matches[1].ToLowerInvariant()
    $tail = $Matches[2].Replace('\', '/')
    return "/mnt/$drive/$tail"
}

if ([string]::IsNullOrWhiteSpace($AiorsRepo)) {
    $AiorsRepo = Find-Repository -StartPath $deployRoot -RepositoryName 'aiors_bsp'
}
if ([string]::IsNullOrWhiteSpace($SvxLinkRepo)) {
    $SvxLinkRepo = Find-Repository -StartPath $deployRoot -RepositoryName 'svxlink'
}

$wslDeploy = Convert-ToWslPath $deployRoot
$wslAiors = Convert-ToWslPath $AiorsRepo
$wslSvxLink = Convert-ToWslPath $SvxLinkRepo
$wslSigningKey = $null
if (-not [string]::IsNullOrWhiteSpace($MinisignSecretKey)) {
    $wslSigningKey = Convert-ToWslPath $MinisignSecretKey
}

$rebuildValue = if ($Rebuild) { '1' } else { '0' }
$wslArguments = @(
    '--cd', $wslDeploy,
    'env', "REBUILD=$rebuildValue",
    'sh', 'scripts/package-release.sh',
    $Version, $wslAiors, $wslSvxLink
)
if ($null -ne $wslSigningKey) {
    $wslArguments += $wslSigningKey
}

Write-Host "Packaging AIORS from $AiorsRepo"
Write-Host "Packaging SvxLink from $SvxLinkRepo"
& wsl.exe @wslArguments
if ($LASTEXITCODE -ne 0) {
    throw "Release packaging failed with exit code $LASTEXITCODE"
}

$outputDir = Join-Path (Join-Path $deployRoot 'dist') $Version
$assetNames = @(
    'aiors-arm64.tar.gz',
    'svxlink-arm64-rootfs.tar.gz',
    'deployment-manifest.env',
    'SHA256SUMS'
)
$signaturePath = Join-Path $outputDir 'SHA256SUMS.minisig'
if (Test-Path -LiteralPath $signaturePath) {
    $assetNames += 'SHA256SUMS.minisig'
}

Write-Host "Release assets ready in $outputDir"

if ($CreateDraft) {
    if (-not (Test-Path -LiteralPath $signaturePath)) {
        throw 'Refusing to create a release draft without SHA256SUMS.minisig.'
    }
    if ($null -eq (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw 'GitHub CLI is required for -CreateDraft. Install it and run gh auth login.'
    }

    $assetPaths = foreach ($assetName in $assetNames) {
        Join-Path $outputDir $assetName
    }
    $notes = "Combined ARM64 AIORS and SvxLink deployment $Version."
    $ghArguments = @(
        'release', 'create', $Version,
        '--repo', $ReleaseRepo,
        '--title', "AIORS Deployment $Version",
        '--notes', $notes,
        '--draft'
    )
    $ghArguments += $assetPaths
    & gh @ghArguments
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub draft release creation failed with exit code $LASTEXITCODE"
    }
}
