@echo off
setlocal EnableExtensions

rem Usage:
rem   tools\windows\build_gsplat_vs2019.bat
rem Optional:
rem   set NS_CONDA_ENV=nerfstudio310
rem   set NS_CONDA_PREFIX="C:\Users\<YOU>\miniconda3\envs\nerfstudio310"
rem   set NS_TORCH_CUDA_ARCH_LIST=12.0+PTX
rem   set NS_GSPLAT_REF=main
rem   set VS2019_BUILDTOOLS="C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools"

rem Avoid UnicodeEncodeError in Rich/tyro on legacy Windows codepages.
chcp 65001 >nul
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

set "NS_CONDA_ENV=%NS_CONDA_ENV%"
if "%NS_CONDA_ENV%"=="" set "NS_CONDA_ENV=nerfstudio310"

set "NS_GSPLAT_REF=%NS_GSPLAT_REF%"
if "%NS_GSPLAT_REF%"=="" set "NS_GSPLAT_REF=main"

if "%NS_TORCH_CUDA_ARCH_LIST%"=="" (
  set "TORCH_CUDA_ARCH_LIST=12.0+PTX"
) else (
  set "TORCH_CUDA_ARCH_LIST=%NS_TORCH_CUDA_ARCH_LIST%"
)

set "VS2019_BUILDTOOLS=%VS2019_BUILDTOOLS%"
if "%VS2019_BUILDTOOLS%"=="" set "VS2019_BUILDTOOLS=C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools"

set "VSDEVCMD=%VS2019_BUILDTOOLS%\Common7\Tools\VsDevCmd.bat"
if not exist "%VSDEVCMD%" (
  echo ERROR: Could not find VsDevCmd.bat at "%VSDEVCMD%"
  exit /b 1
)

call "%VSDEVCMD%" -arch=x64 -host_arch=x64
if errorlevel 1 exit /b %errorlevel%

set DISTUTILS_USE_SDK=1

set "NS_CONDA_PREFIX=%NS_CONDA_PREFIX%"
if "%NS_CONDA_PREFIX%"=="" set "NS_CONDA_PREFIX=%USERPROFILE%\miniconda3\envs\%NS_CONDA_ENV%"

set "PYTHON_EXE=%NS_CONDA_PREFIX%\python.exe"
if not exist "%PYTHON_EXE%" (
  echo ERROR: Could not find python.exe at "%PYTHON_EXE%"
  echo Set NS_CONDA_PREFIX to your conda env path, for example:
  echo   set NS_CONDA_PREFIX=C:\Users\%USERNAME%\miniconda3\envs\%NS_CONDA_ENV%
  exit /b 1
)

rem Put conda env binaries on PATH without running conda activate scripts (these can interfere with VS toolchains).
set "PATH=%NS_CONDA_PREFIX%\Library\bin;%NS_CONDA_PREFIX%\Scripts;%NS_CONDA_PREFIX%;%PATH%"
set "CONDA_PREFIX=%NS_CONDA_PREFIX%"

rem Prefer CUDA 12.8 for torch+cu128 / sm_120 builds.
rem First choice: conda-provided nvcc at %CONDA_PREFIX%\Library\bin\nvcc.exe.
set "NS_CUDA_ROOT="
if not "%CONDA_PREFIX%"=="" (
  if exist "%CONDA_PREFIX%\Library\bin\nvcc.exe" set "NS_CUDA_ROOT=%CONDA_PREFIX%\Library"
)
if "%NS_CUDA_ROOT%"=="" if not "%CUDA_HOME%"=="" (
  if exist "%CUDA_HOME%\bin\nvcc.exe" set "NS_CUDA_ROOT=%CUDA_HOME%"
)
if "%NS_CUDA_ROOT%"=="" if not "%CUDA_PATH%"=="" (
  if exist "%CUDA_PATH%\bin\nvcc.exe" set "NS_CUDA_ROOT=%CUDA_PATH%"
)
if "%NS_CUDA_ROOT%"=="" (
  if exist "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin\nvcc.exe" set "NS_CUDA_ROOT=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8"
)
if "%NS_CUDA_ROOT%"=="" (
  echo ERROR: Could not find nvcc.exe for CUDA 12.8.
  echo - Found nvcc on PATH:
  where nvcc 2>nul
  echo - Recommended fix ^(conda^):
  echo   conda install -n %NS_CONDA_ENV% -y -c nvidia cuda-nvcc=12.8
  echo - Alternative fix ^(system install^):
  echo   Install CUDA Toolkit 12.8 so nvcc exists at:
  echo     C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin\nvcc.exe
  exit /b 1
)

for %%I in ("%NS_CUDA_ROOT%") do set "CUDA_HOME=%%~sI"
set "CUDA_PATH=%CUDA_HOME%"

rem Ensure the CUDA toolkit that matches torch is first on PATH.
set "PATH=%CUDA_HOME%\bin;%PATH%"
set "CUDA_NVCC_EXECUTABLE=%CUDA_HOME%\bin\nvcc.exe"

where cl >nul 2>nul
if errorlevel 1 (
  echo ERROR: cl.exe not found in PATH after VsDevCmd. Check your VS installation.
  exit /b 1
)

where nvcc
nvcc --version

%PYTHON_EXE% -c "import sys, torch; print('python', sys.version.split()[0], 'torch', torch.__version__, 'cuda', torch.version.cuda)"
echo TORCH_CUDA_ARCH_LIST=%TORCH_CUDA_ARCH_LIST%
echo CUDA_HOME=%CUDA_HOME%

rem Torch's Windows extension build expects CUDA libs under %CUDA_HOME%\lib\x64\.
if not exist "%CUDA_HOME%\lib\x64\cudart.lib" (
  if exist "%CUDA_HOME%\lib\cudart.lib" (
    if not exist "%CUDA_HOME%\lib\x64" mkdir "%CUDA_HOME%\lib\x64" >nul 2>nul
    copy /y "%CUDA_HOME%\lib\cudart.lib" "%CUDA_HOME%\lib\x64\cudart.lib" >nul
  )
)

%PYTHON_EXE% -m pip uninstall -y gsplat
%PYTHON_EXE% -m pip install -v --no-build-isolation git+https://github.com/nerfstudio-project/gsplat.git@%NS_GSPLAT_REF%

%PYTHON_EXE% -c "import gsplat; from gsplat.rendering import rasterization; print('gsplat', gsplat.__version__, 'ok')"


