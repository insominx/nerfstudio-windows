## GauStudio on Windows: build playbook (distilled from nerfstudio)

This is a practical checklist for getting CUDA-heavy PyTorch projects building and running on Windows reliably.
It was written after the Windows “splatfacto/gsplat” experience in this repo and is intended to reduce iteration time when you attempt GauStudio (`GAP-LAB-CUHK-SZ/gaustudio`).

### Goals

- Use **one** Python environment, **one** torch+CUDA runtime, and a **matching** nvcc toolchain.
- Avoid Windows-specific footguns: missing MSVC environment, CUDA paths with spaces, encoding issues, and GPU arch mismatches.

---

## 1) Pre-flight checklist (do this once)

### Install prerequisites

- **Git** for Windows
- **Visual Studio Build Tools 2019 or 2022**
  - Install the **Desktop Development with C++** workload
  - Ensure you have an MSVC toolset (v142/v143)
- **NVIDIA driver** (new enough for your GPU)

### Know your GPU architecture

Run:

```powershell
python -c "import torch; print(torch.cuda.get_device_name(0)); print('cap', torch.cuda.get_device_capability(0))"
```

- For RTX 50xx / Blackwell, capability may be **(12, 0)** (sm_120). That often means you must build some CUDA extensions from source with a PTX fallback.

---

## 2) Create a clean conda env (recommended)

Use Python **3.10** on Windows unless the target project explicitly requires something else.

```powershell
conda create -n gaustudio310 -y python=3.10
conda activate gaustudio310
python -m pip install -U pip setuptools wheel
```

Why: wheel availability (and avoiding source builds) tends to be best on 3.10.

---

## 3) Install PyTorch first (choose a CUDA runtime and stick to it)

Pick a torch build whose CUDA runtime you can also provide an nvcc for.

Example (CUDA 12.8 runtime):

```powershell
pip install --index-url https://download.pytorch.org/whl/cu128 torch torchvision
```

Sanity check:

```powershell
python -c "import torch; print('torch', torch.__version__); print('torch.cuda', torch.version.cuda); print('cuda ok', torch.cuda.is_available()); print('cap', torch.cuda.get_device_capability(0))"
```

Rules of thumb:

- **Do not mix** a torch `+cuXYZ` runtime with a different nvcc toolchain.
- If you later change torch CUDA runtime (e.g. cu118 → cu128), rebuild any CUDA extensions.

---

## 4) Provide a matching nvcc (prefer conda `cuda-nvcc`)

Do this if GauStudio (or its submodules) compile CUDA code.

Example (pairs well with torch `+cu128`):

```powershell
conda install -n gaustudio310 -y -c nvidia cuda-nvcc=12.8
```

Verify what nvcc you’ll actually use:

```powershell
where nvcc
nvcc --version
```

If `where nvcc` finds an older system CUDA first, fix your PATH for the build shell so the env’s nvcc wins.

---

## 5) Always build from a shell that has MSVC loaded

Many failures on Windows come down to: **`cl.exe` not on PATH**.

Preferred options:

- Use a **Developer Command Prompt** / **Developer PowerShell** for VS, or
- Run `vcvars64.bat` before building.

Check:

```powershell
where cl
cl
```

If `where cl` fails, nothing CUDA/C++ will build.

---

## 6) Avoid CUDA path spaces + Windows process/encoding traps

### CUDA path with spaces

If your CUDA install is under `C:\Program Files\...`, some build steps can fail when spawning processes.
Mitigations:

- Prefer conda-provided nvcc/tooling (paths under your env, usually no spaces)
- If you must point to system CUDA, set `CUDA_HOME` to a **short path (8.3)**.

### Console encoding

If a script crashes with `UnicodeEncodeError` (common with Rich):

```powershell
chcp 65001
setx PYTHONUTF8 1
```

(You may need a new shell after `setx`.)

---

## 7) Set CUDA arch list when building on newer GPUs

If your GPU is newer than what prebuilt wheels target (e.g. sm_120), build with PTX fallback so the driver can JIT.

```powershell
set TORCH_CUDA_ARCH_LIST=12.0+PTX
```

Notes:

- Only set this when compiling extensions; don’t leave it lying around globally unless you intend it.
- If torch/build tooling rejects the arch, your stack is too old for that GPU.

---

## 8) GauStudio-specific install/build flow (from upstream README)

Upstream sequence (Ubuntu-tested, but the same shape applies on Windows):

- Install dependencies
- Build the custom rasterizer (a submodule)
- Install GauStudio itself

Suggested Windows attempt (from repo root of GauStudio):

```powershell
# In your activated gaustudio310 env
pip install -r requirements.txt

# If the project uses a CUDA/C++ rasterizer submodule:
cd submodules\gaustudio-diff-gaussian-rasterization
python setup.py install
cd ..\..\

# Install the main package (depending on how GauStudio structures packaging)
python setup.py develop
```

If it uses `pyproject.toml` / PEP517 instead of `setup.py`, prefer:

```powershell
pip install -e .
```

---

## 9) Fast failure triage (what to check first)

When a build fails, collect these immediately:

```powershell
python -c "import sys; print(sys.version)"
python -c "import torch; print('torch', torch.__version__, 'cuda', torch.version.cuda, 'avail', torch.cuda.is_available()); print('cap', torch.cuda.get_device_capability(0))"
where cl
where nvcc
nvcc --version
```

Common root causes and fixes:

- **`cl.exe` missing** → open VS dev shell or run `vcvars64.bat`
- **nvcc mismatch** (torch says cu128 but nvcc is 11.x) → install matching `cuda-nvcc` and ensure it’s first on PATH
- **“no kernel image is available”** → extension built without your GPU’s SM; rebuild with `TORCH_CUDA_ARCH_LIST=<sm>+PTX`
- **Process creation fails / paths** → avoid `Program Files` CUDA paths or use short paths; prefer conda nvcc
- **Random compile errors in third-party deps** → try Python 3.10, upgrade pip, and prefer wheels (avoid forced source builds)

---

## 10) Strategy recommendation

- If Windows-native builds get messy, try **WSL2** (Linux toolchains are generally less fragile for CUDA extensions).
- Otherwise: stick to the playbook above—**single conda env**, **torch CUDA runtime aligned with nvcc**, **MSVC env loaded**, and **explicit arch list** for new GPUs.
