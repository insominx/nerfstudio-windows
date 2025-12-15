param(
  [Parameter(Position = 0)]
  [string] $ConfigPath,

  [Parameter(Position = 1)]
  [string] $OutputDir,

  [ValidateSet("legacy", "gaustudio")]
  [string] $ExportFormat = "legacy",

  [ValidateSet("sh_coeffs", "rgb")]
  [string] $PlyColorMode = "sh_coeffs",

  [string] $OutputFilename = "splat.ply",

  [int] $GauStudioIteration = 0,

  [ValidateSet("train", "eval", "all")]
  [string] $GauStudioSplit = "train",

  [string] $GauStudioOutputPlyName = "point_cloud.ply",

  [string] $DefaultsConfigPath,

  [string] $CondaEnv = $env:NS_CONDA_ENV,
  [string] $CondaPrefix = $env:NS_CONDA_PREFIX
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\.."))

$defaultsConfigPath = $null
$defaultsConfigPathFull = $null
$defaultsOutputDir = $null
$defaultsExportFormat = $null
$defaultsPlyColorMode = $null
$defaultsOutputFilename = $null
$defaultsGsIteration = $null
$defaultsGsSplit = $null
$defaultsGsOutputPlyName = $null

$defaultsConfigCandidate = if (-not [string]::IsNullOrWhiteSpace($DefaultsConfigPath)) {
  $DefaultsConfigPath
} else {
  (Join-Path $repoRoot "tools\windows\export_splat_run.defaults.json")
}

if (Test-Path -LiteralPath $defaultsConfigCandidate) {
  try {
    $defaultsConfigPath = $defaultsConfigCandidate
    $defaultsConfigPathFull = (Resolve-Path -LiteralPath $defaultsConfigCandidate).Path
    $defaultsObj = (Get-Content -LiteralPath $defaultsConfigCandidate -Raw | ConvertFrom-Json)

    if ($null -ne $defaultsObj -and $null -ne $defaultsObj.input) {
      if ($null -ne $defaultsObj.input.config_path) { $defaultsConfigPath = [string]$defaultsObj.input.config_path }
    }

    if ($null -ne $defaultsObj -and $null -ne $defaultsObj.export) {
      if ($null -ne $defaultsObj.export.format) { $defaultsExportFormat = [string]$defaultsObj.export.format }
      if ($null -ne $defaultsObj.export.ply_color_mode) { $defaultsPlyColorMode = [string]$defaultsObj.export.ply_color_mode }
      if ($null -ne $defaultsObj.export.output_filename) { $defaultsOutputFilename = [string]$defaultsObj.export.output_filename }
      if ($null -ne $defaultsObj.export.output_dir) { $defaultsOutputDir = [string]$defaultsObj.export.output_dir }
    }

    if ($null -ne $defaultsObj -and $null -ne $defaultsObj.gaustudio_splat) {
      if ($null -ne $defaultsObj.gaustudio_splat.iteration) { $defaultsGsIteration = [int]$defaultsObj.gaustudio_splat.iteration }
      if ($null -ne $defaultsObj.gaustudio_splat.split) { $defaultsGsSplit = [string]$defaultsObj.gaustudio_splat.split }
      if ($null -ne $defaultsObj.gaustudio_splat.output_ply_name) { $defaultsGsOutputPlyName = [string]$defaultsObj.gaustudio_splat.output_ply_name }
    }
  } catch {
    throw "Failed to parse defaults config at '$defaultsConfigCandidate'. Ensure it is valid JSON."
  }
}

if (-not $PSBoundParameters.ContainsKey("ConfigPath") -and -not [string]::IsNullOrWhiteSpace($defaultsConfigPath)) {
  $ConfigPath = $defaultsConfigPath
}
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
  throw "ConfigPath is required. Pass it as the first argument or set input.config_path in '$defaultsConfigCandidate'."
}

$configPathFull = (Resolve-Path -LiteralPath $ConfigPath).Path

if (-not $PSBoundParameters.ContainsKey("ExportFormat") -and -not [string]::IsNullOrWhiteSpace($defaultsExportFormat)) {
  $ExportFormat = $defaultsExportFormat
}
if (-not $PSBoundParameters.ContainsKey("PlyColorMode") -and -not [string]::IsNullOrWhiteSpace($defaultsPlyColorMode)) {
  $PlyColorMode = $defaultsPlyColorMode
}
if (-not $PSBoundParameters.ContainsKey("OutputFilename") -and -not [string]::IsNullOrWhiteSpace($defaultsOutputFilename)) {
  $OutputFilename = $defaultsOutputFilename
}
if (-not $PSBoundParameters.ContainsKey("OutputDir") -and -not [string]::IsNullOrWhiteSpace($defaultsOutputDir)) {
  $OutputDir = $defaultsOutputDir
}
if (-not $PSBoundParameters.ContainsKey("GauStudioIteration") -and $null -ne $defaultsGsIteration) {
  $GauStudioIteration = $defaultsGsIteration
}
if (-not $PSBoundParameters.ContainsKey("GauStudioSplit") -and -not [string]::IsNullOrWhiteSpace($defaultsGsSplit)) {
  $GauStudioSplit = $defaultsGsSplit
}
if (-not $PSBoundParameters.ContainsKey("GauStudioOutputPlyName") -and -not [string]::IsNullOrWhiteSpace($defaultsGsOutputPlyName)) {
  $GauStudioOutputPlyName = $defaultsGsOutputPlyName
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $runDir = Split-Path -Parent $configPathFull
  $OutputDir = Join-Path $runDir "exports"
}

if ([string]::IsNullOrWhiteSpace($CondaEnv)) {
  $CondaEnv = "nerfstudio310"
}
if ([string]::IsNullOrWhiteSpace($CondaPrefix)) {
  $CondaPrefix = Join-Path (Join-Path $HOME "miniconda3\envs") $CondaEnv
}

$nsExportExe = Join-Path (Join-Path $CondaPrefix "Scripts") "ns-export.exe"
if (!(Test-Path $nsExportExe)) {
  $nsExportExe = "ns-export"
}

$exportDirFull = $OutputDir
if (-not [System.IO.Path]::IsPathRooted($exportDirFull)) {
  $exportDirFull = Join-Path $repoRoot $exportDirFull
}
$exportDirFull = [System.IO.Path]::GetFullPath($exportDirFull)

New-Item -ItemType Directory -Path $exportDirFull -Force | Out-Null

# Keep Rich happy on Windows.
chcp 65001 | Out-Null
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

if ($ExportFormat -eq "gaustudio") {
  & $nsExportExe gaustudio-splat --load-config $configPathFull --output-dir $exportDirFull --iteration $GauStudioIteration --split $GauStudioSplit --ply-color-mode $PlyColorMode --output-ply-name $GauStudioOutputPlyName
  if ($LASTEXITCODE -ne 0) { throw "Export gaustudio-splat failed with exit code $LASTEXITCODE" }
} else {
  & $nsExportExe gaussian-splat --load-config $configPathFull --output-dir $exportDirFull --output-filename $OutputFilename --ply-color-mode $PlyColorMode
  if ($LASTEXITCODE -ne 0) { throw "Export gaussian-splat failed with exit code $LASTEXITCODE" }
  & $nsExportExe cameras --load-config $configPathFull --output-dir $exportDirFull
  if ($LASTEXITCODE -ne 0) { throw "Export cameras failed with exit code $LASTEXITCODE" }
}

Write-Host "Export complete: $exportDirFull"