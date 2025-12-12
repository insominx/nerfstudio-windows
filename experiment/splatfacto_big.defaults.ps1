function Get-SplatfactoBigDefaults {
  @(
    "--max-num-iterations=30000",

    # Resolution / sharpness
    "--pipeline.model.rasterize_mode=antialiased",
    "--pipeline.model.num_downscales=0",
    "--pipeline.model.resolution_schedule=1000",
    "--pipeline.model.refine_every=50",

    # Regularization (helps reduce long spiky gaussians)
    "--pipeline.model.use_scale_regularization=True",

    # View-dependent color capacity
    "--pipeline.model.sh_degree=5",
    "--pipeline.model.sh_degree_interval=500",

    # Quality: more gaussians, more splitting
    "--pipeline.model.cull_alpha_thresh=0.005",
    "--pipeline.model.stop_split_at=25000",
    "--pipeline.model.densify_grad_thresh=0.0005",

    # Camera optimization (helps fix camera pose errors)
    "--pipeline.model.camera_optimizer.mode=SO3xR3",

    # Bilateral grid (handles exposure/color shifts in real captures)
    "--pipeline.model.use_bilateral_grid=True",

    # Data handling (fps requires: pip install fpsample)
    "--pipeline.datamanager.cache_images_type=float32"
    # "--pipeline.datamanager.train_cameras_sampling_strategy=fps"
  )
}
