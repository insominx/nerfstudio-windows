# pre-commit

Run through this checklist before every commit to catch common issues.

## Quick Checks

### Tests
- [ ] Do all tests pass? (`dotnet test`)
- [ ] Did I update tests for refactored code?
- [ ] Did I remove tests for deleted code?

### Performance
- [ ] Did I use `GetPixels()` instead of `GetPixel()` for batch texture operations?
- [ ] Am I using ZLinq instead of standard LINQ in hot paths (`Update`)?
- [ ] Did I cache raycast results where applicable?
- [ ] Did I use `StringBuilder` for string building in loops?

### State Management
- [ ] Does this operation use `WorkingState` instead of file I/O?
- [ ] Did I clear temporary state after the operation completes?
- [ ] Is this state already managed elsewhere (duplicate state)?

### Unity Lifecycle
- [ ] Did I allow REQUIRED dependencies to fail loud (no silent null checks)?
- [ ] Did I handle OPTIONAL dependencies gracefully?
- [ ] Am I relying on `Awake()` execution order? Use `Start()` for cross-component setup.

### Architecture
- [ ] Did I create any circular dependencies?
- [ ] Do event names follow `On*` convention?
- [ ] Does dependency flow go: Input → Domain → Infrastructure?

### UI
- [ ] Does this UI work at different aspect ratios (16:9, 16:10, 21:9, 4:3)?
- [ ] Did I test toggle/dropdown click-to-close behavior?
- [ ] Am I using Layout components instead of hardcoded positions?
- [ ] Are fixed controls (pagination, select all) outside scroll content?
- [ ] Did I check Raycast Target settings on non-interactive elements?

### File I/O
- [ ] Did I use `Path.Combine` for path construction?
- [ ] Did I call `Directory.CreateDirectory` before writing?
- [ ] Are paths portable (no absolute/local-machine paths)?
- [ ] Did I sanitize names used in paths (strip "(Clone)", whitespace)?

### Build
- [ ] Did I add new shaders to Graphics Settings "Always Included Shaders"?
- [ ] Are `Resources/` folder assets properly included?
- [ ] Are third-party libraries single-sourced (no duplicate DLLs)?

### Error Handling
- [ ] Do error messages include context, current/expected state, and solutions?

---

## Context-Specific Checks

### If Doing IMGUI/Editor Window Work
- [ ] Wrap groups in `HorizontalScope`/`VerticalScope`
- [ ] Use `Delayed*` fields or gate dirty flags on `MouseUp`
- [ ] Defer heavy work; poll completion in `OnInspectorUpdate`
- [ ] Schedule file pickers via `EditorApplication.delayCall`
- [ ] Call `Repaint()` only when state changes
- [ ] Destroy textures and complete jobs in `OnDisable`/`OnDestroy`

### If Doing Bulk Rename/Refactoring
- [ ] Search for ALL matching patterns first (`TypeName<`, `List<TypeName>`)
- [ ] Check if the type is nested (requires `OuterClass.InnerClass` syntax)
- [ ] Look at existing usages before writing new code

### If Modifying Coroutines/Tasks
- [ ] Do coroutines pass data as parameters instead of shared state?
- [ ] Are coroutine starts guarded to prevent overlapping operations?

### If Working with Bit Encoding
- [ ] Did I verify endianness matches project convention (ABGR little-endian)?
- [ ] Am I using `BitOperations` utilities instead of custom packing?

---

## Related Documentation
- `docs/guides/bug-prevention.md` — Full anti-patterns guide with code examples
- `docs/guides/unity-testing.md` — Test hygiene and integrity rules
- `docs/reference/unity-style-lessons.md` — Refactoring pitfalls
- `docs/reference/imgui-patterns.md` — IMGUI-specific patterns
