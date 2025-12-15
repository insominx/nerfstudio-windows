## Windows + Python + PyTorch (CUDA) build playbook (general principles)

This is a repo-agnostic checklist and set of heuristics for building/running Python projects on Windows that depend on PyTorch and compile CUDA/C++ extensions (custom ops, rasterizers, tiny-cuda-nn-style deps, etc.).

### Core idea: make the toolchain boring

Most “mysterious” Windows build failures collapse into one of these mismatches:

- **Wrong Python** (no wheels → forced source builds; ABI mismatch)
- **Wrong MSVC environment** (`cl.exe` missing or wrong toolset)
- **Wrong CUDA toolchain** (`nvcc` version doesn’t match the PyTorch CUDA runtime you installed)
- **Wrong GPU arch** (extension built without kernels for your GPU)
- **Wrong paths/encoding** (spaces in CUDA paths, Unicode output issues)

### Golden rules (do these first)

- **Use one environment**: one conda/venv for the project; don’t mix “system Python” with your build.
- **Install PyTorch first**: decide on the torch build (`+cuXXX`), then align everything else to it.
- **Keep `torch.version.cuda` and `nvcc --version` aligned** when compiling CUDA code.
- **Build from a shell with MSVC loaded** (Developer Command Prompt/PowerShell or `vcvars64.bat`).
- **Prefer wheels over source builds** on Windows when available (especially for heavy native deps).

## Pre-flight checklist (5 minutes)

### Confirm GPU + torch runtime

Run in the target environment:

```powershell
python -c "import torch; print('torch', torch.__version__); print('torch.cuda', torch.version.cuda); print('available', torch.cuda.is_available()); print('cap', torch.cuda.get_device_capability(0) if torch.cuda.is_available() else None)"
```

Interpretation:

- **`torch.version.cuda`** is the CUDA runtime your PyTorch build expects.
- **`cap`** (compute capability) determines the CUDA arch you must compile for when no wheel supports your GPU yet.

### Confirm MSVC is available (C++/CUDA builds will fail otherwise)

```powershell
where cl
cl
```

If `where cl` fails, open a Visual Studio Developer shell or run `vcvars64.bat` before building.

### Confirm you’re using the intended `nvcc`

```powershell
where nvcc
nvcc --version
```

Common failure: `where nvcc` finds an older system CUDA earlier on PATH than the one you intended.

## Environment strategy (what usually works best)

### Pick a “boring” Python version

- **Python 3.10** tends to have the best wheel availability on Windows for ML stacks.
- Newer Python versions increase the odds you’ll be forced into source builds for native packages.

### Prefer conda-provided nvcc/toolkit components when compiling extensions

If you compile CUDA extensions, having a consistent toolchain inside the env is often more reliable than relying on system-wide CUDA installs.

General principle:

- Use a **single** CUDA toolkit for builds (the one that matches torch’s CUDA runtime).
- Ensure that toolkit’s `bin` is the first `nvcc` found on PATH in the build shell.

### Avoid mixing multiple CUDA installations

On Windows it’s common to have:

- a driver-reported CUDA version (from `nvidia-smi`) and
- multiple toolkits installed (e.g., `v11.8`, `v12.x`) and
- conda-provided `nvcc`

Only one should “win” for builds. If the wrong one wins, you’ll see link errors, compile failures, or runtime kernel incompatibilities.

## GPU architecture + “no kernel image is available”

Symptom:

- `RuntimeError: CUDA error: no kernel image is available for execution on the device`

Meaning:

- The extension binary you installed was compiled without kernels for your GPU’s compute capability.

General fixes:

- **Install a wheel that includes your GPU arch** (best if available).
- **Rebuild from source** with an explicit arch list and/or PTX fallback.

Typical knob (varies by build system):

- `TORCH_CUDA_ARCH_LIST="<major>.<minor>+PTX"` for very new GPUs so the driver can JIT from PTX.

Heuristic:

- If your GPU is newer than what common wheels ship, expect to rebuild extensions and use PTX fallback until official wheels catch up.

## Windows-specific footguns

### CUDA paths with spaces

Many build steps spawn processes and/or quote paths poorly; system CUDA lives under `C:\Program Files\...` which can trigger:

- `CreateProcess failed`
- `nvcc` invocation failures

General mitigations:

- Prefer toolchains located under your env (often no spaces).
- When forced to use system CUDA, use **short paths (8.3)** for build-time environment variables.

### Console encoding (Rich / Unicode output)

Symptom:

- `UnicodeEncodeError: 'charmap' codec can't encode characters ...`

Mitigation for scripts/build output:

- set the console to UTF-8 and force Python UTF-8 mode in that shell (or in your launcher script).

### NumPy ABI mismatches (common with older torch stacks)

Symptom patterns:

- “compiled using NumPy 1.x cannot be run in NumPy 2.x”
- “Failed to initialize NumPy: _ARRAY_API not found”

Meaning:

- Your installed PyTorch (or another native dep) was compiled against a different NumPy major ABI than what you have installed.

Fix:

- Install a NumPy version compatible with your torch build (often pinning `numpy<2` for older torch versions).

## Packaging/build system heuristics

### Prefer wheels; treat forced source builds as “toolchain required”

If pip is building from source on Windows, assume you need:

- MSVC toolset loaded (`cl.exe`)
- matching `nvcc` (for CUDA extensions)
- `ninja`/CMake where relevant

### Rebuild native extensions whenever you change these

If you change any of the following, assume you must reinstall/rebuild compiled deps:

- Python minor version
- PyTorch version or CUDA runtime variant (`+cu118` → `+cu128`)
- CUDA toolkit used for compilation
- GPU arch target list

### Avoid “half-activated” environments

If a build works in one shell but not another, it’s usually because:

- PATH differs (wrong `nvcc`, wrong `cl`, wrong Python)
- environment activation scripts were partially applied

Heuristic:

- Use a consistent launcher (or a Dev Shell) that sets MSVC + PATH deterministically.

## Fast failure triage: what to paste into an issue

These 30 seconds of output usually identify the root cause:

```powershell
python -c "import sys; print('python', sys.version)"
python -c "import torch; print('torch', torch.__version__, 'torch.cuda', torch.version.cuda, 'available', torch.cuda.is_available())"
python -c "import platform; print('platform', platform.platform())"
where python
where cl
where nvcc
nvcc --version
```

## When to stop fighting Windows

If you’re repeatedly blocked by a fragile native toolchain (especially multiple CUDA/C++ extensions), a practical strategy is:

- move the build to **WSL2/Linux** (toolchains and dependency wheels are often more mature), or
- use a known-good Windows launcher that loads MSVC and pins CUDA/toolchain paths for builds.

