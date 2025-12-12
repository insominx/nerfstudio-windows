@echo off
setlocal EnableExtensions

rem Bootstraps a local venv (no conda) suitable for splatfacto on Windows.
rem Requires:
rem - Python 3.10 (recommended)
rem - Visual Studio 2019 Build Tools (for cl.exe)
rem - CUDA Toolkit 12.8 installed (for nvcc)
rem - Git installed (for gsplat source install)

rem Usage:
rem   tools\windows\bootstrap_splatfacto_venv_vs2019.bat
rem Optional:
rem   set VS2019_BUILDTOOLS=C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools
rem   set NS_TORCH_CUDA_ARCH_LIST=12.0+PTX
rem   set NS_CUDA_ROOT=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8

rem Avoid UnicodeEncodeError in Rich/tyro on legacy Windows codepages.
chcp 65001 >nul
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8
set PIP_DISABLE_PIP_VERSION_CHECK=1

for %%I in ("%~dp0..\..") do set "REPO_ROOT=%%~fI"
set "VENV_DIR=%REPO_ROOT%\.venv"
set "VENV_PY=%VENV_DIR%\Scripts\python.exe"

if not exist "%VENV_PY%" (
  set "PY_LAUNCH="
  if not "%NS_PY_VER%"=="" (
    set "PY_LAUNCH=py -%NS_PY_VER%"
    goto have_python
  )

  where py >nul 2>nul
  if errorlevel 0 (
    for %%V in (3.12 3.11 3.10) do (
      py -%%V -c "import sys; assert sys.version_info[:2] >= (3, 10)" >nul 2>nul && set "PY_LAUNCH=py -%%V"
      if not "%PY_LAUNCH%"=="" goto have_python
    )
  )

  where python >nul 2>nul
  if errorlevel 0 (
    python -c "import sys; assert sys.version_info[:2] >= (3, 10)" >nul 2>nul && set "PY_LAUNCH=python"
  )

  :have_python
  if "%PY_LAUNCH%"=="" (
    echo ERROR: No suitable Python found.
    echo - Install Python 3.10+ from python.org (recommended)
    echo - Or install a newer Python via the Windows Store / winget so `py -3.12` works
    echo - Optional override: set NS_PY_VER=3.12  (or 3.11 / 3.10)
    exit /b 1
  )

  echo Creating venv at "%VENV_DIR%" using %PY_LAUNCH%...
  call %PY_LAUNCH% -m venv "%VENV_DIR%"
  if errorlevel 1 (
    echo ERROR: Failed to create venv.
    exit /b %errorlevel%
  )
)

"%VENV_PY%" -m pip install --upgrade pip setuptools wheel
if errorlevel 1 exit /b %errorlevel%

rem Install PyTorch CUDA 12.8 build.
rem If the exact pin isn't available for this Python version, fall back to the latest cu128 builds.
"%VENV_PY%" -m pip install --upgrade --index-url https://download.pytorch.org/whl/cu128 torch==2.7.1+cu128 torchvision==0.22.1+cu128
if errorlevel 1 (
  echo Falling back to latest torch/torchvision cu128 wheels...
  "%VENV_PY%" -m pip install --upgrade --index-url https://download.pytorch.org/whl/cu128 torch torchvision
)
if errorlevel 1 exit /b %errorlevel%

rem Install nerfstudio from this repo.
"%VENV_PY%" -m pip install -e "%REPO_ROOT%"
if errorlevel 1 exit /b %errorlevel%

rem Build/install gsplat from source for sm_120 (PTX fallback) using VS toolchain + nvcc.
set "VS2019_BUILDTOOLS=%VS2019_BUILDTOOLS%"
if "%VS2019_BUILDTOOLS%"=="" set "VS2019_BUILDTOOLS=C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools"
set "VSDEVCMD=%VS2019_BUILDTOOLS%\Common7\Tools\VsDevCmd.bat"
if not exist "%VSDEVCMD%" (
  echo ERROR: Could not find VsDevCmd.bat at "%VSDEVCMD%"
  exit /b 1
)

set "TORCH_CUDA_ARCH_LIST=12.0+PTX"
if not "%NS_TORCH_CUDA_ARCH_LIST%"=="" set "TORCH_CUDA_ARCH_LIST=%NS_TORCH_CUDA_ARCH_LIST%"

set "NS_CUDA_ROOT=%NS_CUDA_ROOT%"
if "%NS_CUDA_ROOT%"=="" set "NS_CUDA_ROOT=%CUDA_HOME%"
if "%NS_CUDA_ROOT%"=="" set "NS_CUDA_ROOT=%CUDA_PATH%"
if "%NS_CUDA_ROOT%"=="" set "NS_CUDA_ROOT=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8"
for %%I in ("%NS_CUDA_ROOT%") do set "CUDA_HOME=%%~sI"
set "CUDA_PATH=%CUDA_HOME%"

call "%VSDEVCMD%" -arch=x64 -host_arch=x64
if errorlevel 1 exit /b %errorlevel%

set "PATH=%CUDA_HOME%\bin;%VENV_DIR%\Scripts;%PATH%"
set "CUDA_NVCC_EXECUTABLE=%CUDA_HOME%\bin\nvcc.exe"

echo Using venv: %VENV_DIR%
"%VENV_PY%" -c "import sys, torch; print('python', sys.version.split()[0], 'torch', torch.__version__, 'cuda', torch.version.cuda)"
echo TORCH_CUDA_ARCH_LIST=%TORCH_CUDA_ARCH_LIST%
echo CUDA_HOME=%CUDA_HOME%

where cl >nul 2>nul
if errorlevel 1 (
  echo ERROR: cl.exe not found in PATH after VsDevCmd.
  exit /b 1
)
where nvcc >nul 2>nul
if errorlevel 1 (
  echo ERROR: nvcc.exe not found. Install CUDA Toolkit 12.8 and/or set NS_CUDA_ROOT.
  exit /b 1
)
where git >nul 2>nul
if errorlevel 1 (
  echo ERROR: git.exe not found. Install Git for Windows (needed to install gsplat from source).
  exit /b 1
)

rem Torch's Windows extension build expects CUDA libs under %CUDA_HOME%\lib\x64\.
if not exist "%CUDA_HOME%\lib\x64\cudart.lib" (
  if exist "%CUDA_HOME%\lib\cudart.lib" (
    if not exist "%CUDA_HOME%\lib\x64" mkdir "%CUDA_HOME%\lib\x64" >nul 2>nul
    copy /y "%CUDA_HOME%\lib\cudart.lib" "%CUDA_HOME%\lib\x64\cudart.lib" >nul
  )
)

"%VENV_PY%" -m pip install -U ninja
if errorlevel 1 exit /b %errorlevel%

"%VENV_PY%" -m pip uninstall -y gsplat
"%VENV_PY%" -m pip install -v --no-build-isolation git+https://github.com/nerfstudio-project/gsplat.git@main
if errorlevel 1 exit /b %errorlevel%

"%VENV_PY%" -c "import gsplat; from gsplat.rendering import rasterization; print('gsplat', getattr(gsplat, '__version__', 'unknown'), 'ok')"
if errorlevel 1 exit /b %errorlevel%

echo Done.

