param(
  [Parameter(Position = 0)]
  [string] $DataPath,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $ExtraArgs = @(),

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

$defaultsScript = Join-Path $repoRoot "experiment\splatfacto_big.defaults.ps1"
$defaults = @()
if (Test-Path -LiteralPath $defaultsScript) {
  . $defaultsScript
  if (Get-Command Get-SplatfactoBigDefaults -ErrorAction SilentlyContinue) {
    $defaults = @(Get-SplatfactoBigDefaults)
  }
}

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
if (!(Test-Path $pythonExe)) {
  throw "python.exe not found at '$pythonExe'. Set NS_CONDA_PREFIX or NS_CONDA_ENV."
}
if (!(Test-Path $nsTrainExe)) {
  throw "ns-train.exe not found at '$nsTrainExe'. Install nerfstudio into this env (pip install -e .)."
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

$escaped = @{
  VsDevCmd = $vsDevCmd.Replace('"', '""')
  CondaPrefix = $CondaPrefix.Replace('"', '""')
  PythonExe = $pythonExe.Replace('"', '""')
  NsTrainExe = $nsTrainExe.Replace('"', '""')
  DataPath = $dataPathFull.Replace('"', '""')
}

$allArgs = @($defaults + $ExtraArgs)
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

  'set "DEFAULT_ARGS="',
  'if not "%NS_QUIT_ON_TRAIN_COMPLETION%"=="" set "DEFAULT_ARGS=--viewer.quit-on-train-completion True"',

  """$($escaped.NsTrainExe)"" $method %DEFAULT_ARGS% $allArgsJoined $dataset --data ""$($escaped.DataPath)"""
)

$tempCmd = Join-Path $env:TEMP ("ns-run-" + $method + "-" + [guid]::NewGuid().ToString("N") + ".cmd")
try {
  Set-Content -LiteralPath $tempCmd -Value $cmdLines -Encoding Ascii
  cmd.exe /d /e:on /v:off /c ('"' + $tempCmd + '"')
} finally {
  Remove-Item -LiteralPath $tempCmd -ErrorAction SilentlyContinue
}
