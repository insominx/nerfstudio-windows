@echo off
setlocal EnableExtensions

rem Usage:
rem   tools\windows\run_splatfacto_vs2019.bat data/nerfstudio/poster
rem Optional:
rem   set NS_CONDA_ENV=nerfstudio310
rem   set NS_CONDA_PREFIX="C:\Users\<YOU>\miniconda3\envs\nerfstudio310"
rem   set VS2019_BUILDTOOLS="C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools"

if "%~1"=="" (
  echo Usage: %~nx0 ^<data_path^>
  exit /b 2
)

rem Avoid UnicodeEncodeError in Rich on legacy Windows codepages.
chcp 65001 >nul
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

rem Help torch/gsplat JIT builds on Windows:
rem - Avoid spaces in CUDA paths (ninja/CreateProcess can choke on unquoted paths).
rem - Ensure the extension targets your GPU architecture (override if needed).
set "NS_CUDA_ROOT=%CUDA_HOME%"
if "%NS_CUDA_ROOT%"=="" set "NS_CUDA_ROOT=%CUDA_PATH%"
if "%NS_CUDA_ROOT%"=="" set "NS_CUDA_ROOT=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8"
for %%I in ("%NS_CUDA_ROOT%") do set "CUDA_HOME=%%~sI"
set "CUDA_PATH=%CUDA_HOME%"
if not "%NS_TORCH_CUDA_ARCH_LIST%"=="" set "TORCH_CUDA_ARCH_LIST=%NS_TORCH_CUDA_ARCH_LIST%"

set "DATA_PATH=%~1"
shift
set "NS_CONDA_ENV=%NS_CONDA_ENV%"
if "%NS_CONDA_ENV%"=="" if not "%CONDA_DEFAULT_ENV%"=="" set "NS_CONDA_ENV=%CONDA_DEFAULT_ENV%"
if "%NS_CONDA_ENV%"=="" set "NS_CONDA_ENV=nerfstudio310"

set "NS_CONDA_PREFIX=%NS_CONDA_PREFIX%"
if "%NS_CONDA_PREFIX%"=="" set "NS_CONDA_PREFIX=%USERPROFILE%\miniconda3\envs\%NS_CONDA_ENV%"
set "PYTHON_EXE=%NS_CONDA_PREFIX%\python.exe"
set "NS_TRAIN_EXE=%NS_CONDA_PREFIX%\Scripts\ns-train.exe"
if not exist "%PYTHON_EXE%" (
  echo ERROR: Could not find python.exe at "%PYTHON_EXE%"
  echo Set NS_CONDA_PREFIX to your conda env path, for example:
  echo   set NS_CONDA_PREFIX=C:\Users\%USERNAME%\miniconda3\envs\%NS_CONDA_ENV%
  exit /b 1
)
if not exist "%NS_TRAIN_EXE%" (
  echo ERROR: Could not find ns-train.exe at "%NS_TRAIN_EXE%"
  echo Install nerfstudio into this env, for example:
  echo   "%PYTHON_EXE%" -m pip install -e .
  exit /b 1
)

set "VS2019_BUILDTOOLS=%VS2019_BUILDTOOLS%"
if "%VS2019_BUILDTOOLS%"=="" set "VS2019_BUILDTOOLS=C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools"

set "VSDEVCMD=%VS2019_BUILDTOOLS%\Common7\Tools\VsDevCmd.bat"
if not exist "%VSDEVCMD%" (
  echo ERROR: Could not find VsDevCmd.bat at "%VSDEVCMD%"
  echo Set VS2019_BUILDTOOLS to your Visual Studio 2019 BuildTools/VS install directory.
  exit /b 1
)

call "%VSDEVCMD%" -arch=x64 -host_arch=x64
if errorlevel 1 exit /b %errorlevel%

rem Put conda env binaries on PATH without running conda activate scripts.
set "PATH=%NS_CONDA_PREFIX%\Library\bin;%NS_CONDA_PREFIX%\Scripts;%NS_CONDA_PREFIX%;%PATH%"
set "CONDA_PREFIX=%NS_CONDA_PREFIX%"

where cl >nul 2>nul
if errorlevel 1 (
  echo ERROR: cl.exe not found in PATH after VsDevCmd. Check your VS installation.
  exit /b 1
)

%PYTHON_EXE% -c "import torch; print('torch', torch.__version__, 'cuda', torch.version.cuda, 'is_available', torch.cuda.is_available())"
%PYTHON_EXE% -c "import sys, gsplat; print('python', sys.version); print('gsplat', getattr(gsplat, '__version__', 'unknown'), gsplat.__file__)"
%PYTHON_EXE% -c "from gsplat.rendering import rasterization; print('gsplat rasterization import ok')"

set "EXTRA_ARGS="
:collect_args
if "%~1"=="" goto run_train
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto collect_args

:run_train
set "DATASET=nerfstudio-data"
if exist "%DATA_PATH%\transforms_train.json" set "DATASET=blender-data"
if exist "%DATA_PATH%\colmap\sparse\0\cameras.txt" set "DATASET=colmap"
if exist "%DATA_PATH%\colmap\sparse\0\cameras.bin" set "DATASET=colmap"

rem Default behavior: keep viewer running (acts like a server).
rem For quick smoke tests, you can opt-in to auto-exit:
rem   set NS_QUIT_ON_TRAIN_COMPLETION=1
set "DEFAULT_ARGS="
if not "%NS_QUIT_ON_TRAIN_COMPLETION%"=="" set "DEFAULT_ARGS=--viewer.quit-on-train-completion True"
%NS_TRAIN_EXE% splatfacto %DEFAULT_ARGS% %EXTRA_ARGS% %DATASET% --data "%DATA_PATH%"
