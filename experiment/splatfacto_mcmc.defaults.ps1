function Get-SplatfactoMcmcDefaults {
  @(
    # Keep this at 30000 for comparisons unless you explicitly want longer.
    "--max-num-iterations=30000",

    # Resolution / sharpness
    "--pipeline.model.rasterize_mode=antialiased",
    "--pipeline.model.num_downscales=0",
    "--pipeline.model.resolution_schedule=1000",
    "--pipeline.model.refine_every=50",

    # View-dependent color capacity
    "--pipeline.model.sh_degree=4",
    "--pipeline.model.sh_degree_interval=500",

    # Pruning / refinement schedule (tune to taste)
    "--pipeline.model.cull_alpha_thresh=0.005",
    "--pipeline.model.stop_split_at=25000",

    # Regularization
    "--pipeline.model.use_scale_regularization=True",

    # Pose/exposure fixes
    "--pipeline.model.camera_optimizer.mode=SO3xR3",
    "--pipeline.model.use_bilateral_grid=True",

    # Data handling
    "--pipeline.datamanager.cache_images_type=float32"
  )
}
