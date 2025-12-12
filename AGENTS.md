## Agent Quickstart (`nerfstudio` repo)

This file is the **fastest path to being productive** in this repo (especially on Windows). It’s intentionally “big picture first”, with copy/paste commands and pointers to the few files you’ll touch most.

### What this repo is

`nerfstudio` is a framework + CLI for training and viewing NeRF-style methods (including Gaussian Splatting via `splatfacto`).

- **CLI entrypoint**: `ns-train` (and friends like `ns-process-data`, `ns-viewer`) are defined in `pyproject.toml` under `[project.scripts]`.
- **Primary training command**: `ns-train <method> ...`
- **Viewer**: typically runs at `http://localhost:7007` during training.

### Repo layout (where to look first)

- **`nerfstudio/`**: core Python package.
  - **Training loop**: `nerfstudio/engine/trainer.py`
  - **Pipelines**: `nerfstudio/pipelines/`
  - **Models**: `nerfstudio/models/` (e.g., `splatfacto.py`)
  - **Data parsing / loading**:
    - dataparsers: `nerfstudio/data/dataparsers/`
    - datamanagers: `nerfstudio/data/datamanagers/` (e.g., `full_images_datamanager.py`)
- **`docs/`**: official docs content (Sphinx / mkdocs-style content).
- **`tools/windows/`**: Windows helper scripts (VS toolchain + CUDA quirks).
- **`tiny-cuda-nn/`**: a gitlink/submodule (CUDA-heavy dependency); not required for all methods but relevant for CUDA extension work.

### The one-file dependency truth

Project dependencies are declared in `pyproject.toml` under `[project.dependencies]`.

Important nuance:
- `gsplat==1.4.0; sys_platform != 'win32'` is pinned for non-Windows.
- On Windows we may install/build a newer `gsplat` for CUDA/arch reasons; pip may warn but this is expected on win32.

### Fast “am I working?” checks

From an activated env:

```powershell
python -c "import importlib.metadata as md; print('nerfstudio', md.version('nerfstudio'))"
python -c "import torch; print('torch', torch.__version__, 'cuda', torch.version.cuda, 'ok', torch.cuda.is_available()); print('cap', torch.cuda.get_device_capability(0))"
python -c "from gsplat.rendering import rasterization; print('gsplat rasterization import ok')"
ns-train --help
```

### Windows (recommended workflow)

Windows is workable, but CUDA extensions are sensitive to:
- having **MSVC** available (`cl.exe`)
- having **nvcc that matches torch’s CUDA runtime**
- CUDA paths containing spaces (`Program Files`) causing process-spawn failures
- CUDA import library layout differences (`cudart.lib`)

#### Windows: fastest path for splatfacto + CUDA builds

Use the scripts in `tools/windows/` rather than reproducing the toolchain setup by hand:

- **Build/install `gsplat` from source (main)**: `tools/windows/build_gsplat_vs2019.bat`
  - Handles:
    - loading VS dev environment
    - selecting conda env python
    - CUDA 12.8 nvcc discovery (conda `cuda-nvcc`)
    - ensuring `cudart.lib` exists where the linker expects it (`CUDA_HOME\\lib\\x64\\cudart.lib`)
    - sets `TORCH_CUDA_ARCH_LIST` (defaults to `12.0+PTX`)
- **Run splatfacto with VS toolchain loaded**: `tools/windows/run_splatfacto_vs2019.bat` (or `.ps1`)
  - Auto-selects dataset type:
    - if `transforms_train.json` exists: `blender-data`
    - else if `colmap/sparse/0/cameras.txt` or `colmap/sparse/0/cameras.bin` exists: `colmap`
    - else: `nerfstudio-data` (expects `transforms.json`)

See also: `tools/windows/README.md` for usage and troubleshooting.

#### Windows: reference setup used on this machine (RTX 5080 / sm_120)

This is the “known good” path documented in `BUILD_INVESTIGATION.md`:

```powershell
conda create -n nerfstudio310 -y python=3.10
conda activate nerfstudio310

conda install -n nerfstudio310 -y -c nvidia cuda-nvcc=12.8

pip install -e .

set NS_CONDA_ENV=nerfstudio310
set NS_GSPLAT_REF=main
tools\windows\build_gsplat_vs2019.bat

tools\windows\run_splatfacto_vs2019.bat data\nerfstudio\poster --max-num-iterations 1
```

If you are *not* on Blackwell (e.g. RTX 4090 = sm_89), the same scripts still work; you can typically use a smaller arch list (e.g. `NS_TORCH_CUDA_ARCH_LIST=8.9+PTX`) or often avoid building from source if a compatible prebuilt wheel exists.

### Common workflows (what agents usually need)

#### Train

```powershell
ns-train nerfacto nerfstudio-data --data data/nerfstudio/poster
ns-train splatfacto nerfstudio-data --data data/nerfstudio/poster
```

On Windows, prefer running splatfacto through:
- `tools/windows/run_splatfacto_vs2019.bat`

#### Process data

```powershell
ns-process-data --help
```

Datasets are typically placed under `data/` (repo root).

#### Where to change splatfacto behavior

- Model config / defaults: `nerfstudio/models/splatfacto.py`
- Data caching / image loading behavior: `nerfstudio/data/datamanagers/full_images_datamanager.py`

#### Add a new method (high-level)

1) Create a model config + model under `nerfstudio/models/`.
2) Wire it into method registration (search for method registries/usages in the codebase).
3) Ensure the CLI config (Tyro) can construct it.
4) Smoke test via `ns-train <yourmethod> ...`.

### “Gotchas” that waste time

- **Conda activation scripts can interfere with MSVC env** on Windows. If builds behave strangely, use the provided scripts which avoid fragile activation patterns.
- **`where nvcc` lying**: you can have CUDA 11.8 on PATH even when torch is `+cu128`. Fix by installing `cuda-nvcc=12.8` into the env and ensuring it is first on PATH for builds.
- **`cudart.lib` missing**: conda puts it under `%CONDA_PREFIX%\\Library\\lib`. Many builds expect `%CUDA_HOME%\\lib\\x64`. The Windows build script normalizes this.
- **pip dependency “conflict” warnings** on Windows for gsplat version pins: check `pyproject.toml` markers before assuming something is broken.

### Key docs to read (in order)

1) `tools/windows/README.md` (Windows-specific execution + failure modes)
2) `BUILD_INVESTIGATION.md` (narrative of what broke + why + exact repro)
3) `docs/quickstart/installation.md` (general install guidance; may not include the newest GPU/toolchain edge cases)


