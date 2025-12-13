param(
  [Parameter(Position = 0)]
  [string] $DataPath,

  [switch] $SmokeExport,

  [switch] $ExportSplat,

  [ValidateSet("sh_coeffs", "rgb")]
  [string] $PlyColorMode = "sh_coeffs",

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $ExtraArgs = @(),

  [string] $ExportDir,

  [string] $RunTimestamp,

  [string] $CondaEnv = $env:NS_CONDA_ENV,
  [string] $CondaPrefix = $env:NS_CONDA_PREFIX,
  [string] $Vs2019BuildTools = $env:VS2019_BUILDTOOLS
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\.."))

if ([string]::IsNullOrWhiteSpace($DataPath)) {
  $DataPath = (Join-Path $repoRoot "experiment\lego")
}

$defaults = @()
$defaultsConfig = Join-Path $repoRoot "tools\windows\splatfacto_big.defaults.json"
$exportCfgEnabled = $false
$exportCfgPlyColorMode = $null
$exportCfgExportDir = $null
$exportCfgTimestamp = $null
if (Test-Path -LiteralPath $defaultsConfig) {
  try {
    $defaultsObj = (Get-Content -LiteralPath $defaultsConfig -Raw | ConvertFrom-Json)
    if ($null -ne $defaultsObj -and $null -ne $defaultsObj.cli_args) {
      $defaults = @($defaultsObj.cli_args)
    }
    if ($null -ne $defaultsObj -and $null -ne $defaultsObj.export_splat) {
      if ($null -ne $defaultsObj.export_splat.enabled) { $exportCfgEnabled = [bool]$defaultsObj.export_splat.enabled }
      if ($null -ne $defaultsObj.export_splat.ply_color_mode) { $exportCfgPlyColorMode = [string]$defaultsObj.export_splat.ply_color_mode }
      if ($null -ne $defaultsObj.export_splat.export_dir) { $exportCfgExportDir = [string]$defaultsObj.export_splat.export_dir }
      if ($null -ne $defaultsObj.export_splat.timestamp) { $exportCfgTimestamp = [string]$defaultsObj.export_splat.timestamp }
    }
  } catch {
    throw "Failed to parse defaults config at '$defaultsConfig'. Ensure it is valid JSON."
  }
}

$exportSplatEffective = if ($PSBoundParameters.ContainsKey("ExportSplat")) { [bool]$ExportSplat } else { $exportCfgEnabled }
$plyColorModeEffective = if ($PSBoundParameters.ContainsKey("PlyColorMode")) { $PlyColorMode } elseif (-not [string]::IsNullOrWhiteSpace($exportCfgPlyColorMode)) { $exportCfgPlyColorMode } else { $PlyColorMode }
$exportDirEffective = if ($PSBoundParameters.ContainsKey("ExportDir")) { $ExportDir } elseif (-not [string]::IsNullOrWhiteSpace($exportCfgExportDir)) { $exportCfgExportDir } else { $ExportDir }
$timestampEffective = if ($PSBoundParameters.ContainsKey("RunTimestamp")) { $RunTimestamp } elseif (-not [string]::IsNullOrWhiteSpace($exportCfgTimestamp)) { $exportCfgTimestamp } else { $RunTimestamp }
$doExportEffective = $SmokeExport -or $exportSplatEffective

if ([string]::IsNullOrWhiteSpace($CondaEnv)) {
  $CondaEnv = "nerfstudio310"
}
if ([string]::IsNullOrWhiteSpace($Vs2019BuildTools)) {
  $Vs2019BuildTools = "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools"
}
if ([string]::IsNullOrWhiteSpace($CondaPrefix)) {
  $CondaPrefix = Join-Path (Join-Path $HOME "miniconda3\envs") $CondaEnv
}

$pythonExe = Join-Path $CondaPrefix "python.exe"
$nsTrainExe = Join-Path (Join-Path $CondaPrefix "Scripts") "ns-train.exe"
$nsExportExe = Join-Path (Join-Path $CondaPrefix "Scripts") "ns-export.exe"
if (!(Test-Path $pythonExe)) {
  throw "python.exe not found at '$pythonExe'. Set NS_CONDA_PREFIX or NS_CONDA_ENV."
}
if (!(Test-Path $nsTrainExe)) {
  throw "ns-train.exe not found at '$nsTrainExe'. Install nerfstudio into this env (pip install -e .)."
}
if ($doExportEffective -and !(Test-Path $nsExportExe)) {
  throw "ns-export.exe not found at '$nsExportExe'. Install nerfstudio into this env (pip install -e .)."
}

$vsDevCmd = Join-Path $Vs2019BuildTools "Common7\Tools\VsDevCmd.bat"
if (!(Test-Path $vsDevCmd)) {
  throw "VsDevCmd.bat not found at '$vsDevCmd'. Set VS2019_BUILDTOOLS to your VS2019 install root."
}

$dataPathFull = (Resolve-Path -LiteralPath $DataPath).Path
$colmapCamerasTxt = Join-Path $dataPathFull "colmap\sparse\0\cameras.txt"
$colmapCamerasBin = Join-Path $dataPathFull "colmap\sparse\0\cameras.bin"
if (!(Test-Path $colmapCamerasTxt) -and !(Test-Path $colmapCamerasBin)) {
  throw "No COLMAP sparse model found under '$dataPathFull'. Expected '$colmapCamerasTxt' (or cameras.bin)."
}

$method = "splatfacto-big"
$dataset = "colmap"

$experimentName = Split-Path -Leaf $dataPathFull
$ExportSplat = $exportSplatEffective
$PlyColorMode = $plyColorModeEffective
$ExportDir = $exportDirEffective
$RunTimestamp = $timestampEffective
$doExport = $doExportEffective
$resolvedTimestamp = if ($doExport) {
  if ([string]::IsNullOrWhiteSpace($RunTimestamp)) { Get-Date -Format "yyyy-MM-dd_HHmmss" } else { $RunTimestamp }
} else {
  ""
}

$configYmlPath = if ($doExport) {
  Join-Path $repoRoot ("outputs\{0}\splatfacto\{1}\config.yml" -f $experimentName, $resolvedTimestamp)
} else {
  ""
}
$resolvedExportDir = if ([string]::IsNullOrWhiteSpace($ExportDir)) {
  Join-Path $repoRoot "exports\splat"
} else {
  $p = $ExportDir
  if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $repoRoot $p }
  [System.IO.Path]::GetFullPath($p)
}
if ($doExport -and !(Test-Path -LiteralPath $resolvedExportDir)) {
  New-Item -ItemType Directory -Path $resolvedExportDir -Force | Out-Null
}
$exportFilename = if ($doExport) { ("{0}-{1}.ply" -f $method, $resolvedTimestamp) } else { "" }

$escaped = @{
  VsDevCmd = $vsDevCmd.Replace('"', '""')
  CondaPrefix = $CondaPrefix.Replace('"', '""')
  PythonExe = $pythonExe.Replace('"', '""')
  NsTrainExe = $nsTrainExe.Replace('"', '""')
  NsExportExe = $nsExportExe.Replace('"', '""')
  DataPath = $dataPathFull.Replace('"', '""')
  ConfigYmlPath = $configYmlPath.Replace('"', '""')
  ExportDir = $resolvedExportDir.Replace('"', '""')
  ExportFilename = $exportFilename.Replace('"', '""')
  PlyColorMode = $PlyColorMode.Replace('"', '""')
}

$smokeArgs = if ($SmokeExport) {
  @(
    "--max-num-iterations=100",
    ("--experiment-name={0}" -f $experimentName),
    ("--timestamp={0}" -f $resolvedTimestamp)
  )
} else {
  @()
}

$exportArgs = if ($ExportSplat -and -not $SmokeExport) {
  @(
    ("--experiment-name={0}" -f $experimentName),
    ("--timestamp={0}" -f $resolvedTimestamp)
  )
} else {
  @()
}

$allArgs = @($defaults + $ExtraArgs + $smokeArgs + $exportArgs)
$allArgsQuoted = $allArgs | ForEach-Object { '"' + $_.Replace('"', '""') + '"' }
$allArgsJoined = $allArgsQuoted -join ' '

# NOTE: cmd.exe /c does not reliably execute multi-line strings; write a temp .cmd script instead.
$cmdLines = @(
  '@echo off',
  'setlocal EnableExtensions',
  'chcp 65001 >nul',
  'set PYTHONUTF8=1',
  'set PYTHONIOENCODING=utf-8',

  'set "NS_CUDA_ROOT=%CUDA_HOME%"',
  'if "%NS_CUDA_ROOT%"=="" set "NS_CUDA_ROOT=%CUDA_PATH%"',
  'if "%NS_CUDA_ROOT%"=="" set "NS_CUDA_ROOT=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8"',
  'for %%I in ("%NS_CUDA_ROOT%") do set "CUDA_HOME=%%~sI"',
  'set "CUDA_PATH=%CUDA_HOME%"',
  'if not "%NS_TORCH_CUDA_ARCH_LIST%"=="" set "TORCH_CUDA_ARCH_LIST=%NS_TORCH_CUDA_ARCH_LIST%"',

  "call ""$($escaped.VsDevCmd)"" -arch=x64 -host_arch=x64",
  'if errorlevel 1 exit /b %errorlevel%',

  "set ""PATH=$($escaped.CondaPrefix)\Library\bin;$($escaped.CondaPrefix)\Scripts;$($escaped.CondaPrefix);%PATH%""",
  "set ""CONDA_PREFIX=$($escaped.CondaPrefix)""",

  'where cl >nul 2>nul',
  'if errorlevel 1 ( echo ERROR: cl.exe not found in PATH after VsDevCmd. Check your VS installation. & exit /b 1 )',

  """$($escaped.PythonExe)"" -c ""import torch; print('torch', torch.__version__, 'cuda', torch.version.cuda, 'is_available', torch.cuda.is_available())""",
  """$($escaped.PythonExe)"" -c ""import sys, gsplat; print('python', sys.version); print('gsplat', getattr(gsplat, '__version__', 'unknown'), gsplat.__file__)""",
  """$($escaped.PythonExe)"" -c ""from gsplat.rendering import rasterization; print('gsplat rasterization import ok')""",

  'if not "%NS_DO_EXPORT%"=="" set "NS_QUIT_ON_TRAIN_COMPLETION=1"',
  'set "DEFAULT_ARGS="',
  'if not "%NS_QUIT_ON_TRAIN_COMPLETION%"=="" set "DEFAULT_ARGS=--viewer.quit-on-train-completion True"',

  """$($escaped.NsTrainExe)"" $method %DEFAULT_ARGS% $allArgsJoined $dataset --data ""$($escaped.DataPath)""",
  'if errorlevel 1 exit /b %errorlevel%',
  'if "%NS_DO_EXPORT%"=="" goto :eof',
  """$($escaped.NsExportExe)"" gaussian-splat --load-config ""$($escaped.ConfigYmlPath)"" --output-dir ""$($escaped.ExportDir)"" --output-filename ""$($escaped.ExportFilename)"" --ply-color-mode ""$($escaped.PlyColorMode)"""
)

$tempCmd = Join-Path $env:TEMP ("ns-run-" + $method + "-" + [guid]::NewGuid().ToString("N") + ".cmd")
try {
  Set-Content -LiteralPath $tempCmd -Value $cmdLines -Encoding Ascii
  if ($doExport) {
    cmd.exe /d /e:on /v:off /c ('set "NS_DO_EXPORT=1" && "' + $tempCmd + '"')
  } else {
    cmd.exe /d /e:on /v:off /c ('"' + $tempCmd + '"')
  }
} finally {
  Remove-Item -LiteralPath $tempCmd -ErrorAction SilentlyContinue
}
