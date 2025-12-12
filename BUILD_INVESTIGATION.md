# Nerfstudio Build Investigation Report

## Overview

**Nerfstudio** is a modular framework for Neural Radiance Field (NeRF) development, created by Berkeley AI Research (BAIR). It provides a simplified end-to-end process for creating, training, and testing NeRFs with a focus on modularity and collaboration.

This report was updated after attempting an actual install on this machine. The earlier draft contained a few incorrect assumptions (notably around required Python version and Windows-native build breakpoints). The steps below are written to be reproducible on Windows 11.

- **Version**: 1.1.5
- **License**: Apache 2.0
- **Repository**: https://github.com/nerfstudio-project/nerfstudio

---

## Current System Hardware Assessment

### GPU
| Property | Value |
|----------|-------|
| **Model** | NVIDIA GeForce RTX 5080 |
| **VRAM** | 16,303 MiB |
| **Driver Version** | 581.29 |
| **CUDA Version (Driver)** | 13.0 |
| **Compute Capability** | 12.0 (Blackwell architecture) |

### CPU & System
| Property | Value |
|----------|-------|
| **CPU** | AMD Ryzen 9 9950X3D 16-Core Processor |
| **RAM** | 63,032 MB (~64 GB) |
| **OS** | Microsoft Windows 11 Pro (Build 26200) |
| **System Type** | x64-based PC |

### Current Software Environment
| Component | Installed Version | Required Version |
|-----------|-------------------|------------------|
| **System Python** | 3.13.6 | Not recommended for this repo on Windows |
| **Conda env Python (nerfstudio310)** | 3.10.19 | >= 3.8.0 (repo requirement); 3.10 recommended on Windows |
| **CUDA Toolkit (nvcc)** | 12.8 (V12.8.93, via conda `cuda-nvcc`) | Must match the PyTorch CUDA runtime when building CUDA extensions from source |
| **PyTorch** | 2.7.1+cu128 | CUDA-enabled build required; compile extensions with sm_120 / PTX fallback |
| **Miniconda** | (installed) | ✅ Provides conda-compatible environment |

---

## Compatibility Analysis

### Critical Issues

1. **Python Version Mismatch**
   - **Installed**: Python 3.13.6
   - **Repo requirement**: `requires-python = ">=3.8.0"` (@pyproject.toml)
   - **Pixi (Linux-only)**: `python = ">=3.8,<3.11"` (@pixi.toml)
   - **Verified**: Installation succeeded on Windows using a conda env with **Python 3.8.20**.
   - **Action**: Use Python **3.8–3.10** on Windows; do not use system Python 3.13 for this repo.

2. **CUDA Version Alignment**
   - **Installed (nvcc)**: CUDA 12.8
   - **Installed (driver)**: CUDA 13.0 (from `nvidia-smi`)
   - **Observed**: Using **PyTorch cu118** works, but shows a warning for RTX 5080 sm_120 support.
   - **Action**: If you compile CUDA extensions (e.g., tiny-cuda-nn) from source, align `CUDA_HOME`/PATH to one toolkit and ensure your PyTorch build matches.

3. **Miniconda Installed** ✅
   - Base conda distribution is installed; use `conda` commands for environment management

4. **RTX 5080 (Blackwell) Architecture**
   - CUDA architecture: **sm_120** (compute capability 12.0)
   - Dockerfile default architectures: `90;89;86;80;75;70;61` (no sm_120)
   - PyTorch cu118 build used here supports CUDA architectures up to **sm_90**, and emits a warning on sm_120 GPUs.
   - CUDA ops can still run (PTX/JIT fallback), but performance/feature coverage may be limited until you use a PyTorch build that includes **sm_120**.

---

## Observed Build Attempts (Windows 11, Dec 11-12, 2025)

### Final working stack (RTX 5080 / sm_120, Windows 11)

This is the configuration that successfully:
- builds `gsplat` from source, and
- runs `ns-train splatfacto` on an RTX 5080 (sm_120).

**Key idea**: keep `torch` CUDA runtime and `nvcc` aligned (CUDA 12.8 here), and compile `gsplat` with `TORCH_CUDA_ARCH_LIST=12.0+PTX` so Blackwell can JIT PTX.

#### Repro steps (copy/paste)

```powershell
# 0) Create env
conda create -n nerfstudio310 -y python=3.10
conda activate nerfstudio310

# 1) Install nvcc 12.8 into the env (so nvcc matches torch 2.7.1+cu128)
conda install -n nerfstudio310 -y -c nvidia cuda-nvcc=12.8

# 2) Install PyTorch (CUDA 12.8 build)
pip install --index-url https://download.pytorch.org/whl/cu128 torch==2.7.1+cu128 torchvision==0.22.1+cu128

# 3) Install nerfstudio
pip install -e .

# 4) Build/install gsplat from source (main) for sm_120
set NS_CONDA_ENV=nerfstudio310
set NS_GSPLAT_REF=main
tools\windows\build_gsplat_vs2019.bat

# 5) Verify
python -c "import torch; print('torch', torch.__version__, 'torch.cuda', torch.version.cuda); print('cap', torch.cuda.get_device_capability(0))"
python -c "from gsplat.rendering import rasterization; print('gsplat ok')"

# 6) Smoke test
tools\windows\run_splatfacto_vs2019.bat data\\nerfstudio\\poster --max-num-iterations 1
```

#### Notes / gotchas (why this was needed)

- `where nvcc` may still point at CUDA 11.8 on PATH. `gsplat` will fail to build in that case.
- With conda CUDA packages, `cudart.lib` lives at `%CONDA_PREFIX%\\Library\\lib\\cudart.lib`, but PyTorch extension builds often look for `%CUDA_HOME%\\lib\\x64\\cudart.lib`.
  - `tools\\windows\\build_gsplat_vs2019.bat` now copies `cudart.lib` into the expected `lib\\x64` location automatically.
- You may see a pip warning like: “nerfstudio requires gsplat==1.4.0, but you have gsplat 1.5.3”.
  - In `pyproject.toml`, non-Windows is pinned to `gsplat==1.4.0`, while Windows allows `gsplat>=1.4.0` (to support source builds / newer GPUs).

### Initial Build (Dec 11, 2025)

- **Result**: `pip install -e .` succeeded in the existing conda env (`nerfstudio`, Python 3.8.20).

#### First blocker encountered

- **Failure**: `pip install -e .` initially failed while building `pywinpty` from source (Rust/maturin) with:
  - `LINK : fatal error LNK1181: cannot open input file 'winpty.lib'`

#### Fix

- Installing the prebuilt wheel resolves the issue:

```powershell
pip install --only-binary=:all: pywinpty
```

After that, re-running `pip install -e .` completed successfully.

### Splatfacto-Specific Issues (Dec 12, 2025)

While `ns-train nerfacto` worked, `ns-train splatfacto` failed with multiple Windows-specific issues:

#### Issue 1: gsplat JIT Compilation Failure
- **Problem**: `gsplat` attempted to JIT-compile CUDA extensions on first use, which failed on Windows with `CreateProcess failed: The system cannot find the file specified` errors.
- **Root Cause**: Windows build toolchain (MSVC/nvcc) not properly configured in the environment, and CUDA paths with spaces causing issues.
- **Solution**:
  - **If a compatible wheel exists for your PyTorch/CUDA/GPU**: install a prebuilt `gsplat` wheel from the official wheel index instead of relying on runtime JIT compilation.
  - **If you are on RTX 50xx (sm_120)**: build `gsplat` from source with PTX fallback (see Issue 1b / “Final working stack”). Wheels may not include sm_120 kernels yet.

#### Issue 1b: RTX 5080 (sm_120) "no kernel image is available"
- **Problem**: Training crashes inside `gsplat` with:
  - `RuntimeError: CUDA error: no kernel image is available for execution on the device`
- **Root Cause**: The installed `gsplat` wheel was built without kernels compatible with **sm_120** GPUs.
- **Solution (works today)**: Build `gsplat` from source with PTX fallback so the driver can JIT to sm_120:
  ```powershell
  pip uninstall -y gsplat
  set TORCH_CUDA_ARCH_LIST=12.0+PTX
  pip install -v --no-build-isolation git+https://github.com/nerfstudio-project/gsplat.git@main
  ```
  Note: if you are using an older PyTorch build that rejects `12.0`, use the repo script `tools\windows\build_gsplat_vs2019.bat` which is the canonical Windows path and also fixes `cudart.lib` layout.

#### Issue 2: fpsample Build Failure
- **Problem**: `fpsample` dependency failed to compile on Windows with MSVC errors (`ssize_t: undeclared identifier`).
- **Root Cause**: `fpsample` uses POSIX types not available in MSVC without additional headers.
- **Solution**: Made `fpsample` optional on Windows in `pyproject.toml` and lazy-imported it in code. It's only needed for the `"fps"` camera sampling strategy (default is `"random"`), so `splatfacto` works without it.

#### Issue 3: NumPy 2.x Incompatibility
- **Problem**: NumPy 2.2.6 incompatible with PyTorch 2.1.x, causing `RuntimeError: Numpy is not available`.
- **Root Cause**: PyTorch 2.1.x was compiled against NumPy 1.x ABI, and NumPy 2.x changed the ABI.
- **Solution**: Pin NumPy to < 2.0:
  ```powershell
  pip install -U "numpy<2"
  ```

#### Issue 4: Console Encoding (Rich Unicode)
- **Problem**: `UnicodeEncodeError: 'charmap' codec can't encode characters` when Rich tries to print Unicode box-drawing characters.
- **Root Cause**: Windows console default encoding (cp1252) doesn't support Rich's Unicode output.
- **Solution**: Set UTF-8 encoding in launcher scripts (`chcp 65001` and `PYTHONUTF8=1`).

#### Issue 5: CUDA_HOME Path with Spaces
- **Problem**: CUDA toolkit path `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\` contains spaces, causing `nvcc` invocation failures.
- **Solution**: Use Windows short path (8.3 format) in build environment variables.

### Working Solution for Splatfacto on Windows

This section is preserved for historical context, but the recommended path on RTX 5080 (sm_120) is the “Final working stack” above.

#### Recommended (RTX 5080 / sm_120)

1. **Create Python 3.10 environment**:
   ```powershell
   conda create --name nerfstudio310 -y python=3.10
   conda activate nerfstudio310
   ```

2. **Install PyTorch CUDA 12.8 build**:
   ```powershell
   pip install --index-url https://download.pytorch.org/whl/cu128 torch==2.7.1+cu128 torchvision==0.22.1+cu128
   ```

3. **Install nerfstudio**:
   ```powershell
   pip install -e .
   ```

4. **Install nvcc 12.8 into the env** (so nvcc matches torch `+cu128` when building CUDA extensions):
   ```powershell
   conda install -n nerfstudio310 -y -c nvidia cuda-nvcc=12.8
   ```

5. **Build `gsplat` from source for sm_120**:
   ```powershell
   set NS_CONDA_ENV=nerfstudio310
   set NS_GSPLAT_REF=main
   tools\windows\build_gsplat_vs2019.bat
   ```

6. **Run splatfacto**:
   ```powershell
   tools\windows\run_splatfacto_vs2019.bat data/nerfstudio/poster
   ```

## Dependencies Overview

### Core Dependencies (from pyproject.toml)

| Category | Key Packages |
|----------|-------------|
| **Deep Learning** | `torch>=1.13.1`, `torchvision>=0.14.1`, `torchmetrics[image]>=1.0.1` |
| **NeRF Acceleration** | `nerfacc==0.5.2`, `tiny-cuda-nn` (external), `gsplat` |
| **3D Processing** | `open3d>=0.16.0`, `trimesh>=3.20.2`, `pymeshlab>=2022.2.post2`, `xatlas` |
| **Image/Video** | `opencv-python-headless==4.10.0.84`, `imageio>=2.21.1`, `av>=9.2.0`, `Pillow>=10.3.0` |
| **Visualization** | `viser==1.0.0`, `plotly>=5.7.0`, `matplotlib>=3.6.0`, `mediapy>=1.1.0` |
| **Logging** | `tensorboard>=2.13.0`, `wandb>=0.13.3`, `comet_ml>=3.33.8` |
| **Config/CLI** | `tyro>=0.9.8`, `rich>=12.5.1` |
| **Scientific** | `numpy`, `scipy`, `scikit-image>=0.19.3`, `h5py>=2.9.0` |
| **Optional (Windows)** | `fpsample` - Only needed for `"fps"` camera sampling strategy, automatically skipped on Windows |

**Note on gsplat (Windows)**:
- If a compatible wheel exists for your GPU, installing a wheel is the easiest path.
- For RTX 50xx / sm_120, the reliable approach is to build `gsplat` from source with `TORCH_CUDA_ARCH_LIST=12.0+PTX` using `tools\windows\build_gsplat_vs2019.bat`.

### External Build Dependencies

1. **tiny-cuda-nn** - Must be compiled from source with CUDA support
2. **COLMAP** - For camera pose estimation (optional, for custom data)
3. **Visual Studio 2019 or 2022** - Required on Windows for CUDA compilation

---

## Supported NeRF Methods

### Built-in Methods
| Method | Description |
|--------|-------------|
| **nerfacto** | Recommended method, integrates multiple techniques |
| **splatfacto** | Gaussian Splatting implementation |
| **instant-ngp** | Instant Neural Graphics Primitives |
| **vanilla-nerf** | Original NeRF implementation |
| **mipnerf** | Multiscale anti-aliasing NeRF |
| **tensorf** | Tensorial Radiance Fields |
| **depth-nerfacto** | Nerfacto with depth supervision |
| **neus/neus-facto** | Neural implicit surfaces |
| **semantic-nerfw** | Semantic NeRF in the wild |
| **generfacto** | Generative NeRF |

### Third-party Methods (via plugins)
- Instruct-NeRF2NeRF, LERF, K-Planes, Zip-NeRF, and many more

---

## Build Plan

### Option 1: Conda (Miniconda) Environment (Recommended for Windows)

#### For nerfacto and most methods:

```powershell
# 0. Prefer activating the environment instead of using `conda run`.
#    On this machine, `conda run ...` hit a Windows encoding error (cp1252) when commands printed
#    certain Unicode characters.

# 1. Create an environment (3.10 recommended on Windows)
conda create --name nerfstudio310 -y python=3.10
conda activate nerfstudio310

# 2. Upgrade packaging tools
python -m pip install --upgrade pip setuptools wheel

# 3. Install PyTorch (CUDA-enabled).
#    For RTX 5080 / sm_120, use a CUDA 12.8 build (this machine's working stack).
pip install --index-url https://download.pytorch.org/whl/cu128 torch==2.7.1+cu128 torchvision==0.22.1+cu128

# 4. Preempt a common Windows build failure (pywinpty)
pip install --only-binary=:all: pywinpty

# 5. Install nerfstudio from source (editable)
pip install -e .

# 6. Verify the CLI
ns-train --help
```

#### For splatfacto (Gaussian Splatting):

```powershell
# 1. Create Python 3.10 environment
conda create --name nerfstudio310 -y python=3.10
conda activate nerfstudio310

# 2. Upgrade packaging tools
python -m pip install --upgrade pip setuptools wheel

# 3. Install PyTorch (CUDA-enabled) for RTX 5080 / sm_120
pip install --index-url https://download.pytorch.org/whl/cu128 torch==2.7.1+cu128 torchvision==0.22.1+cu128

# 4. Install nvcc 12.8 into the env (so nvcc matches torch +cu128 when building CUDA extensions)
conda install -n nerfstudio310 -y -c nvidia cuda-nvcc=12.8

# 5. Install nerfstudio (fpsample will be skipped on Windows automatically)
pip install -e .

# 6. Build gsplat from source (sm_120 + PTX fallback) using the repo script
set NS_CONDA_ENV=nerfstudio310
set NS_GSPLAT_REF=main
tools\windows\build_gsplat_vs2019.bat

# 7. Run splatfacto (use launcher script for VS dev environment)
tools\windows\run_splatfacto_vs2019.bat data/nerfstudio/poster
```

#### Notes

- `nerfstudio` does not expose a `nerfstudio.__version__` attribute; use:

```powershell
python -c "import importlib.metadata as md; print(md.version('nerfstudio'))"
```

- If `ns-train` fails to run through `conda run`, use the entrypoint directly:

```powershell
C:\Users\<you>\miniconda3\envs\nerfstudio\Scripts\ns-train.exe --help
```

### Option 1b: tiny-cuda-nn (Optional, source build)

`tiny-cuda-nn` is not a hard dependency of the base `pip install -e .` path above, but some methods/plugins may require it. If you build it on Windows:

- Ensure Visual Studio build tools are installed and discoverable by CMake.
- Ensure you are using a single CUDA toolkit (`CUDA_HOME`/PATH).
- For RTX 5080 (sm_120), you generally need **CUDA >= 12.8** and a compatible PyTorch build.

### Option 2: Docker (Linux recommended, Windows with WSL2)

```bash
# Pull pre-built image
docker pull ghcr.io/nerfstudio-project/nerfstudio:latest

# Or build with custom architectures (note: base image is CUDA 11.8; sm_120 requires a CUDA >= 12.8 base plus matching PyTorch/TCNN/gsplat builds)
docker build --build-arg CUDA_ARCHITECTURES=90 --tag nerfstudio -f Dockerfile .

# Run container
docker run --gpus all \
    -v /path/to/data:/workspace/ \
    -p 7007:7007 \
    --rm -it --shm-size=12gb \
    nerfstudio
```

### Option 3: Pixi (Linux only - not applicable)

Currently only supports `linux-64` platform per `pixi.toml`.

---

## Windows-Specific Requirements

1. **Visual Studio 2019 or 2022** with "Desktop Development with C++" workload
2. **MSVC Toolset** - v143 (VS2022) or v142 (VS2019)
3. **Git** for Windows
4. **CUDA build integration (only if compiling CUDA extensions)**
   - This is only necessary when building CUDA extensions from source (e.g., tiny-cuda-nn).
   - Prefer using the Visual Studio Developer Command Prompt, or ensure `cl.exe` is available to builds.

### Windows Launcher Scripts

For convenience, launcher scripts are provided in `tools/windows/` that automatically:
- Load Visual Studio 2019/2022 developer environment
- Add the conda env binaries to `PATH` (without `conda activate`, to avoid fragile activation scripts)
- Set UTF-8 encoding for Rich console output
- Configure CUDA_HOME with short paths (avoiding spaces)
- Run `ns-train splatfacto` with proper environment

The launchers also auto-select the dataset type:
- If the dataset folder contains `transforms_train.json`, it uses `blender-data`.
- If the dataset folder contains `colmap/sparse/0/cameras.txt` or `colmap/sparse/0/cameras.bin`, it uses `colmap`.
- Otherwise it uses `nerfstudio-data` (expects `transforms.json`).

**Usage**:
```powershell
# From repository root
tools\windows\run_splatfacto_vs2019.bat data/nerfstudio/poster

# Or with PowerShell
pwsh -File tools/windows/run_splatfacto_vs2019.ps1 -DataPath data/nerfstudio/poster
```

**Customization**: Set environment variables before running:
- `NS_CONDA_ENV` - Conda environment name (default: `nerfstudio310`)
- `NS_CONDA_PREFIX` - Conda env path (overrides `NS_CONDA_ENV`)
- `VS2019_BUILDTOOLS` - Path to VS2019 BuildTools (default: `C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools`)
- `NS_QUIT_ON_TRAIN_COMPLETION` - If set, passes `--viewer.quit-on-train-completion True` (useful for short smoke tests)

---

## RTX 5080 (Blackwell) Considerations

The RTX 5080 uses the **Blackwell architecture** (compute capability 12.0), which is very new. Key concerns:

1. **CUDA 11.8 Compatibility**: Default toolchain targets up to sm_90. sm_120 is not generated with CUDA 11.8.

2. **PyTorch build matters**:
   - Older `+cu118` builds may warn that kernels for **sm_120** aren’t included.
   - The working stack for this machine is `torch==2.7.1+cu128` + `cuda-nvcc=12.8`.

3. **tiny-cuda-nn**: sm_120 builds generally require CUDA ≥ 12.8 plus a compatible PyTorch build.

4. **gsplat**: ✅ **WORKING** - Build from source with PTX fallback via `tools\windows\build_gsplat_vs2019.bat` to ensure compatibility with sm_120.

5. **Fallback Option**:
   - Use the working cu118 environment for now and accept the warning.
   - For full Blackwell support, migrate to a PyTorch build that includes **sm_120** and rebuild CUDA extensions against that stack.
   - Current setup works but may have reduced performance due to sm_90 kernel fallback.

---

## Current Status & Blocking Issues (Reflection)

### ✅ Resolved Issues

1. **splatfacto on Windows (RTX 5080 / sm_120)** - **WORKING** ✅
   - Solution: Use `torch==2.7.1+cu128`, `cuda-nvcc=12.8`, build `gsplat` from source with `TORCH_CUDA_ARCH_LIST=12.0+PTX`, and use the Windows launcher scripts in `tools/windows/`.

2. **NumPy 2.x incompatibility** - **CONTEXTUAL** ✅
   - `numpy<2` is needed for older PyTorch 2.1.x stacks.
   - The working `torch==2.7.1+cu128` stack on this machine is compatible with NumPy 2.x.

3. **fpsample build failure** - **RESOLVED** ✅
   - Solution: Made optional on Windows (only needed for `"fps"` camera sampling, default is `"random"`).

### ⚠️ Known Limitations

1. **GPU too new for published wheels**  
   - Provided instructions use cu118 wheels that ship up to sm\_90. No released wheels in this repo include sm\_120 kernels yet.
   - Result: sm\_120 devices run sm\_90 kernels or require custom builds.
   - **Status**: Works but with performance warnings. Full sm\_120 support requires newer PyTorch builds.

2. **Windows toolchain fragility for JIT builds**  
   - tiny-cuda-nn and gsplat may JIT-compile (no matching wheel) and can fail to locate `cl.exe`/`ninja` unless VS build tools are on PATH.
   - **Status**: Avoided by using prebuilt wheels for `gsplat`. For other extensions, use VS Developer Command Prompt or launcher scripts.

3. **Environment mismatches**  
   - Multiple CUDA toolkits (11.8 in env vs 12.x/13.x system) complicate PATH/CUDA_HOME and architecture targeting.
   - **Status**: Managed by using prebuilt wheels and proper environment setup.

### Recommended approach right now

- **For Windows users**:
  1) Use Python 3.10 environment for best wheel availability.
  2) For RTX 50xx / sm_120: use the CUDA 12.8 stack (`torch==2.7.1+cu128`, `cuda-nvcc=12.8`) and build `gsplat` from source (`tools/windows/build_gsplat_vs2019.bat`).
  3) Use Windows launcher scripts (`tools/windows/run_splatfacto_vs2019.bat` / `tools/windows/run_splatfacto_vs2019.ps1`) to ensure VS + CUDA paths are set up consistently.

- **For Linux/WSL2 users**:
  - Linux toolchain inheritance is more stable; easier to build from source or use future wheels once sm\_120 is supported.

- **Future improvements**:
  - Wait for official PyTorch cu13.x sm\_120 wheels and corresponding prebuilt extensions.

---

## CLI Commands Reference

| Command | Purpose |
|---------|---------|
| `ns-train` | Train a NeRF model |
| `ns-viewer` | Launch the web viewer |
| `ns-render` | Render videos from trained models |
| `ns-export` | Export point clouds or meshes |
| `ns-process-data` | Process custom data (images/video) |
| `ns-download-data` | Download sample datasets |
| `ns-eval` | Evaluate trained models |

---

## Quick Start After Installation

```bash
# Download sample data
ns-download-data nerfstudio --capture-name=poster

# Train nerfacto model
ns-train nerfacto --data data/nerfstudio/poster

# Train splatfacto (Gaussian Splatting)
ns-train splatfacto --data data/nerfstudio/poster
```

The web viewer will be available at `http://localhost:7007` during training.

---

## Testing

Run the test suite to verify installation:

```bash
# Install dev dependencies
pip install -e .[dev]

# Run tests
pytest
```

---

## Recommended Next Steps

1. ✅ Miniconda already installed; continue using `conda` for environment management
2. ✅ `pip install -e .` works on Windows in a Python 3.8-3.10 conda env if you preinstall the `pywinpty` wheel
3. ✅ **splatfacto now working on Windows (RTX 5080 / sm_120)** - Use `torch==2.7.1+cu128`, `cuda-nvcc=12.8`, and build `gsplat` from source with PTX fallback
4. **Decide how much you care about sm_120 support**:
   - If you want maximum performance/compatibility on RTX 5080, plan to move to a PyTorch build that ships **sm_120** kernels.
   - Current setup works but shows warnings; performance may be suboptimal until sm_120 support is available.
5. **If you compile CUDA extensions** (tiny-cuda-nn or future wheels fall back to source):
   - Ensure Visual Studio build tools are installed and discoverable.
   - Align `CUDA_HOME`/PATH to a single CUDA toolkit.
   - Use Windows launcher scripts for proper environment setup.
6. **Run a small training** to verify end-to-end:
   - ✅ `nerfacto` - Works out of the box
   - ✅ `splatfacto` - Works when `gsplat` is built from source (PTX fallback) on sm_120

---

## Resources

- **Documentation**: https://docs.nerf.studio/
- **Discord**: https://discord.gg/uMbNqcraFc
- **GitHub Issues**: https://github.com/nerfstudio-project/nerfstudio/issues
- **Paper**: https://arxiv.org/abs/2302.04264

---

*Report updated: December 12, 2025*

**Latest updates**:
- ✅ splatfacto now working on Windows (RTX 5080 / sm_120) by building gsplat from source
- ✅ fpsample made optional on Windows (only needed for "fps" camera sampling)
- ✅ NumPy 2.x note documented (pin `numpy<2` only for older PyTorch 2.1.x stacks)
- ✅ Windows launcher scripts added for VS dev environment setup
- ✅ Console encoding issues resolved (UTF-8 support)
