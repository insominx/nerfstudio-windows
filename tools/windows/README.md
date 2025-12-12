## Windows: run `splatfacto` with VS2019 + conda env

Gaussian splatting (`splatfacto`) uses `gsplat`, which may compile a CUDA extension the first time it runs. On Windows this typically requires the Visual Studio C++ toolchain environment to be loaded (so `cl.exe` is on PATH), and your Python environment binaries to be on `PATH`.

This repo also includes launchers that:
- force UTF-8 output (to avoid Rich `UnicodeEncodeError`)
- set `CUDA_HOME` to a short path (8.3) to avoid Windows process creation issues when CUDA is in `Program Files`
- optionally set `TORCH_CUDA_ARCH_LIST` via `NS_TORCH_CUDA_ARCH_LIST` (only use this if your installed PyTorch recognizes the arch).
- install / rebuild `gsplat` from source (recommended on RTX 50xx / sm_120) via `tools/windows/build_gsplat_vs2019.bat`.

### VS2019 Build Tools + cmd (.bat)

From the repo root:

```bat
tools\windows\run_splatfacto_vs2019.bat data/nerfstudio/poster
```

You can also pass any extra `ns-train` args after the data path, for example:

```bat
tools\windows\run_splatfacto_vs2019.bat data/nerfstudio/poster --max-num-iterations 2
```

Note: the launcher auto-selects the dataset type:
- If the dataset folder contains `transforms_train.json`, it uses `blender-data` (NeRF synthetic / Blender datasets).
- If the dataset folder contains `colmap/sparse/0/cameras.txt` or `colmap/sparse/0/cameras.bin`, it uses `colmap`.
- Otherwise it uses `nerfstudio-data` (expects `transforms.json`).

Overrides (optional):

```bat
set NS_CONDA_ENV=nerfstudio310
set NS_CONDA_PREFIX=C:\Users\<YOU>\miniconda3\envs\nerfstudio310
set VS2019_BUILDTOOLS=C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools
set NS_TORCH_CUDA_ARCH_LIST=12.0+PTX
tools\windows\run_splatfacto_vs2019.bat data/nerfstudio/poster
```

For quick smoke tests where you want the process to exit after training completes, set:

```bat
set NS_QUIT_ON_TRAIN_COMPLETION=1
```

### PowerShell wrapper (.ps1)

```powershell
pwsh -File tools/windows/run_splatfacto_vs2019.ps1 data/nerfstudio/poster
```

Extra args can be passed after the data path:

```powershell
pwsh -File tools/windows/run_splatfacto_vs2019.ps1 data/nerfstudio/poster --max-num-iterations 2
```

### If it still fails

Paste the full traceback, plus:

```powershell
# Use the same Python environment that `ns-train` is running under.
# If you have `NS_CONDA_PREFIX` set, you can run:
& "$env:NS_CONDA_PREFIX\\python.exe" -c "import torch; print(torch.__version__, torch.version.cuda, torch.cuda.is_available())"
& "$env:NS_CONDA_PREFIX\\python.exe" -c "import gsplat; print(gsplat.__version__)"
```

#### Important: Windows `gsplat` wheels are Python-version specific

If you're on **Python 3.8/3.9**, pip will typically fall back to a source install and `gsplat` will try to JIT-compile (`gsplat_cuda`) at runtime (using `nvcc` + MSVC + ninja). That path is fragile on Windows.

If you switch to **Python 3.10**, you may be able to avoid the JIT build by installing a prebuilt `gsplat` wheel from:

`https://docs.gsplat.studio/whl/gsplat/`

Pick the wheel that matches your PyTorch/CUDA combo (the filename includes it), for example:
- `...+pt21cu118-...` for `torch==2.1.x` + CUDA 11.8

#### NumPy version note (important with older PyTorch)

If you see warnings like:
- "A module that was compiled using NumPy 1.x cannot be run in NumPy 2.x"
- "Failed to initialize NumPy: _ARRAY_API not found"

it usually means your environment has **NumPy 2.x** but your installed **PyTorch was built against NumPy 1.x**.

Fix:

```bat
pip install -U "numpy<2"
```

#### RTX 50xx (sm_120) note: gsplat wheels may not include compatible kernels yet

If you hit:

- `RuntimeError: CUDA error: no kernel image is available for execution on the device`

it means your installed `gsplat` binary was built without a compatible kernel for your GPU (RTX 5080 = **sm_120**).

**Fix (works today): build gsplat from source with PTX fallback** so it can JIT on newer GPUs.

This machine’s working combo:
- `torch==2.7.1+cu128` (CUDA 12.8 runtime)
- `cuda-nvcc=12.8` installed into the conda env
- `TORCH_CUDA_ARCH_LIST=12.0+PTX`

Install nvcc into the env:

```bat
conda install -n nerfstudio310 -y -c nvidia cuda-nvcc=12.8
```

Then build gsplat using the repo script (this also fixes `cudart.lib` layout for the linker):

```bat
set NS_CONDA_ENV=nerfstudio310
set NS_GSPLAT_REF=main
tools\windows\build_gsplat_vs2019.bat
```

Then verify:

```bat
python -c "from gsplat.rendering import rasterization; print('gsplat ok')"
```

```bat
REM Manual (if you need to bypass the script)
pip uninstall -y gsplat
set TORCH_CUDA_ARCH_LIST=12.0+PTX
pip install -v --no-build-isolation git+https://github.com/nerfstudio-project/gsplat.git@main
```

Then verify:

```bat
python -c "from gsplat.rendering import rasterization; print('gsplat ok')"
```

If you later move to a PyTorch build that officially supports sm_120, you can also try a newer prebuilt `gsplat` wheel (when available).

