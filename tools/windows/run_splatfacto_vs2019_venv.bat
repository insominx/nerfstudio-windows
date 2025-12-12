@echo off
setlocal EnableExtensions

rem Run splatfacto using a local .venv (no conda), with VS2019 toolchain.
rem First run will auto-bootstrap .venv if needed.

rem Usage:
rem   tools\windows\run_splatfacto_vs2019_venv.bat <data_path> [extra ns-train args...]

if "%~1"=="" (
  echo Usage: %~nx0 ^<data_path^> [extra ns-train args...]
  exit /b 2
)

rem Avoid UnicodeEncodeError in Rich on legacy Windows codepages.
chcp 65001 >nul
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

for %%I in ("%~dp0..\..") do set "REPO_ROOT=%%~fI"
set "VENV_DIR=%REPO_ROOT%\.venv"
set "VENV_PY=%VENV_DIR%\Scripts\python.exe"
set "NS_TRAIN=%VENV_DIR%\Scripts\ns-train.exe"

if not exist "%VENV_PY%" (
  call "%~dp0bootstrap_splatfacto_venv_vs2019.bat"
  if errorlevel 1 exit /b %errorlevel%
)

set "DATA_PATH=%~1"
shift
set "EXTRA_ARGS="
:collect_args
if "%~1"=="" goto run_train
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto collect_args

:run_train
set "VS2019_BUILDTOOLS=%VS2019_BUILDTOOLS%"
if "%VS2019_BUILDTOOLS%"=="" set "VS2019_BUILDTOOLS=C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools"
set "VSDEVCMD=%VS2019_BUILDTOOLS%\Common7\Tools\VsDevCmd.bat"
if not exist "%VSDEVCMD%" (
  echo ERROR: Could not find VsDevCmd.bat at "%VSDEVCMD%"
  exit /b 1
)

set "NS_CUDA_ROOT=%NS_CUDA_ROOT%"
if "%NS_CUDA_ROOT%"=="" set "NS_CUDA_ROOT=%CUDA_HOME%"
if "%NS_CUDA_ROOT%"=="" set "NS_CUDA_ROOT=%CUDA_PATH%"
if "%NS_CUDA_ROOT%"=="" set "NS_CUDA_ROOT=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8"
for %%I in ("%NS_CUDA_ROOT%") do set "CUDA_HOME=%%~sI"
set "CUDA_PATH=%CUDA_HOME%"

call "%VSDEVCMD%" -arch=x64 -host_arch=x64
if errorlevel 1 exit /b %errorlevel%

set "PATH=%CUDA_HOME%\bin;%VENV_DIR%\Scripts;%PATH%"

"%VENV_PY%" -c "import torch; print('torch', torch.__version__, 'cuda', torch.version.cuda, 'is_available', torch.cuda.is_available())"
"%VENV_PY%" -c "import sys, gsplat; print('python', sys.version.split()[0]); print('gsplat', getattr(gsplat, '__version__', 'unknown'), gsplat.__file__)"

set "DATASET=nerfstudio-data"
if exist "%DATA_PATH%\transforms_train.json" set "DATASET=blender-data"
if exist "%DATA_PATH%\colmap\sparse\0\cameras.txt" set "DATASET=colmap"
if exist "%DATA_PATH%\colmap\sparse\0\cameras.bin" set "DATASET=colmap"

"%NS_TRAIN%" splatfacto %EXTRA_ARGS% %DATASET% --data "%DATA_PATH%"

