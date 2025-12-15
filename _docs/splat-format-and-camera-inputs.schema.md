# Schema inputs for GauStudio mesh extraction

This doc describes the **file formats and minimal fields** GauStudio expects to extract a mesh from a trained 3D Gaussian Splatting (“splat”) result.

Primary entrypoint: `gs-extract-mesh` (`gaustudio/scripts/extract_mesh.py`).

---

## 1) Required inputs at a glance

Mesh extraction needs:

1) A **Gaussian point cloud PLY** (3DGS-style) containing per-Gaussian parameters (position, SH color, opacity, scale, rotation).
2) A **camera list** in GauStudio’s `cameras.json` schema (intrinsics + poses).

You can provide these either as:

- **Option A (directory layout)**: `--model` points at a 3DGS output directory.
- **Option B (single PLY)**: `--model` points directly at a `.ply` file, plus `--source_path` points at `cameras.json`.

---

## 2) Input layouts accepted by `gs-extract-mesh`

### Option A: 3DGS-style model directory (recommended)

`--model <model_dir>` where `<model_dir>` contains:

```text
<model_dir>/
  cameras.json
  point_cloud/
    iteration_XXXX/
      point_cloud.ply
```

Notes:
- If `--load_iteration -1` (default), GauStudio loads the **max** `iteration_XXXX` found in `<model_dir>/point_cloud/`.
- `cameras.json` is expected at `<model_dir>/cameras.json` if `--source_path` is not provided.

### Option B: Standalone PLY

`--model <path/to/splat.ply>` (or `point_cloud.ply`) plus one of:

- `--source_path <path/to/cameras.json>` (recommended), or
- `--source_path <colmap_root>` (advanced; uses GauStudio COLMAP dataset loader).

---

## 3) Gaussian “splat” PLY schema (required)

GauStudio expects a **binary little-endian PLY** with `element vertex N` and a set of per-vertex properties matching common 3DGS exports.

### Required vertex properties (by name)

At minimum, a 3DGS gaussian PLY typically includes:

- Position: `x`, `y`, `z` (float)
- Normal (often unused but expected by some loaders): `nx`, `ny`, `nz` (float)
- Spherical-harmonics color:
  - DC terms: `f_dc_0`, `f_dc_1`, `f_dc_2` (float)
  - Higher-order terms: `f_rest_0 ... f_rest_K` (float)
- Opacity: `opacity` (float)
- Anisotropic scale: `scale_0`, `scale_1`, `scale_2` (float)
- Rotation (quaternion): `rot_0`, `rot_1`, `rot_2`, `rot_3` (float)

### SH degree and `f_rest_*` count

The count of `f_rest_*` terms depends on spherical-harmonics degree `D`:

- Number of SH basis terms per channel: `(D + 1)^2`
- DC consumes 1 basis term per channel, so “rest” per channel is `(D + 1)^2 - 1`
- Total `f_rest_*` across RGB is `3 * ((D + 1)^2 - 1)`

Example:
- If `D = 4`, `(D + 1)^2 = 25`, so `f_rest_*` count is `3 * (25 - 1) = 72` (`f_rest_0 .. f_rest_71`).

### What you already have

Your exported `assets/test-model1/exports/splat.ply` header includes the standard 3DGS fields (including `f_rest_0..f_rest_71`, `opacity`, `scale_0..2`, `rot_0..3`), so it matches the expected “splat PLY” shape.

---

## 4) `cameras.json` schema (required)

`cameras.json` is a **JSON array** of camera entries. Each entry must include intrinsics and pose fields that match GauStudio’s loader (`gaustudio/utils/cameras_utils.py` and `gaustudio/datasets/utils.py`).

### Required fields per camera entry

Each camera object must have:

- `id` (integer): unique camera id
- `img_name` (string): image identifier; used for output naming (does not need to point to a real image on disk for mesh extraction)
- `width` (integer): image width in pixels
- `height` (integer): image height in pixels
- `fx` (number): focal length in pixels (x)
- `fy` (number): focal length in pixels (y)
- `cx` (number): principal point x in pixels
- `cy` (number): principal point y in pixels
- `rotation` (3x3 array of numbers): **camera-to-world rotation matrix** (see “Pose convention” below)
- `position` (length-3 array of numbers): **camera center in world coordinates** (see “Pose convention” below)

### Pose convention (important)

GauStudio’s canonical `cameras.json` convention (as produced by `gaustudio/datasets/utils.py:camera_to_JSON`) is **camera-to-world (C2W)**:

- `C2W[:3, :3] = rotation`
- `C2W[:3, 3] = position` (camera center)

Internally, GauStudio inverts this to obtain a world-to-camera matrix for rendering and projection.

If you generate `cameras.json` using GauStudio’s own helper `camera_to_JSON(...)`, you will automatically match this convention.

### Minimal example entry

```json
[
  {
    "id": 0,
    "img_name": "00000.png",
    "width": 1920,
    "height": 1080,
    "fx": 1500.0,
    "fy": 1500.0,
    "cx": 960.0,
    "cy": 540.0,
    "rotation": [[1,0,0],[0,1,0],[0,0,1]],
    "position": [0,0,0]
  }
]
```

---

## 5) Why Nerfstudio’s `transforms_*.json` is not enough (in your case)

Your Nerfstudio export includes:

- `assets/test-model1/exports/transforms_train.json`
- `assets/test-model1/exports/transforms_eval.json`

These files contain entries with:

- `file_path`
- a 3x4 `transform` matrix

But they **do not include intrinsics** (`fx/fy/cx/cy`, `width/height`), and their field names do not match GauStudio’s `cameras.json` schema. So you still need a conversion step (or another source of intrinsics).

Common sources for intrinsics:
- The original COLMAP reconstruction (`cameras.txt` / `images.txt`, or `.bin` equivalents).
- A Nerfstudio-style `transforms.json` that contains per-frame `fl_x`, `fl_y`, `cx`, `cy`, `w`, `h` and `transform_matrix` (GauStudio has a Nerfstudio dataset loader for this format, but your `exports/transforms_*.json` is a different shape).

---

## 6) Quick validation checklist

Before running `gs-extract-mesh`:

- PLY: header contains `x y z`, `f_dc_0..2`, `opacity`, `scale_0..2`, `rot_0..3`, and `f_rest_*` count consistent with your SH degree.
- Cameras JSON: file is a JSON array; each entry has all required fields listed in section 4.
- Poses: generated via GauStudio’s `camera_to_JSON` (recommended) or otherwise verified to match the C2W convention above.

---

## 7) Nerfstudio ↔ GauStudio compatibility issues (root causes)

This section documents the concrete mismatches that commonly break a Nerfstudio → GauStudio mesh-extraction workflow.

### 7.1) Pose *direction* mismatch (C2W vs W2C)

- GauStudio’s `cameras.json` tooling (`camera_to_JSON` / `JSON_to_camera`) is built around **C2W in the JSON** (section 4).
- Nerfstudio’s GauStudio exporter (`nerfstudio/scripts/exporter.py:ExportGauStudioSplat`) currently writes **W2C** fields (`rotation` + `position`) into `cameras.json` (it explicitly converts `c2w -> (R_w2c, t_w2c)` before serializing).

If GauStudio reads that file via its normal `JSON_to_camera(...)` path, it will interpret those values as C2W and effectively invert them again, producing incorrect camera poses.

Practical symptom: renders/depths are empty or wildly off, and TSDF fusion produces garbage or nothing.

### 7.2) Camera axis convention mismatch (OpenGL vs OpenCV/COLMAP)

Even when using C2W consistently, you must also align camera coordinate conventions:

- Nerfstudio’s internal camera convention is **OpenGL/Blender-style** for camera axes.
- When Nerfstudio parses COLMAP, it converts COLMAP(OpenCV) → Nerfstudio(OpenGL) using the standard flip:
  - `c2w[0:3, 1:3] *= -1`
- GauStudio’s Nerfstudio dataset loader performs the inverse conversion (Nerfstudio(OpenGL) → OpenCV) with the same flip before inverting.

If you export Nerfstudio poses and consume them in GauStudio without applying the matching axis conversion, you can get mirrored scenes, points “behind” the camera, or systematically wrong projections.

### 7.3) “Auto pose detection” can mask the issue (but isn’t a fix)

`gaustudio/scripts/extract_mesh.py` has an `--camera_pose_mode auto` option that tries a small grid of pose interpretations (transpose rotation, axis sign flips) and picks the one that projects the most Gaussian points into the image bounds.

This can sometimes make a mismatched `cameras.json` usable for meshing, but it is inherently heuristic and can fail silently depending on the scene, crop, and camera subset.

