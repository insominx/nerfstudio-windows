# implement

Your goal is to **implement** the described feature or fix based on prior research and planning. Execute with precision, avoiding common pitfalls, and get it right on the first try.

## Context

Before implementing, you should have already:
- Completed research/planning (via `/plan` or a `docs/plan/*.md` file)
- Understood the relevant documentation

If the user provides a plan file (e.g., `@docs/plan/feature-x.md`), treat that as the implementation spec.

## Required Reading

Before beginning any implementation, read and internalize these guides:

1. **`@docs/guides/bug-prevention.md`** — Project-specific anti-patterns, pre-commit checklist, and lessons from 470 commits of bug fixes
2. **`@docs/guides/ux-convergence.md`** — Strategies for converging on user intent: single authority, explicit code paths, mental model alignment
3. **`@docs/reference/unity-style-lessons.md`** — Unity-specific patterns: ambiguous types, target-typed `new` pitfalls, namespace cleanup rules, nested class references

These documents encode hard-won lessons. Violating their guidance will likely reproduce historical bugs.

## Project Context

- **Engine:** Unity 6.0+ — avoid deprecated APIs per `@docs/reference/unity-6-api-changes.md`
- **3rd Party:** Never modify files in `Plugins/` or vendor folders unless explicitly instructed

**Repository Map:**
- `Core/` — Runtime systems for schema, painting, identification, and data
- `Painter/` — Brush logic, projective painters, and command systems
- `Mark2Maintain/` — UI flows, CMR logic, Excel integration, photo management
- `Tests/` — Editor and playmode tests
- `Packages/com.humana-machina.editor-tools/` — Editor utilities

## Pre-Implementation Checklist

Before writing code, verify:

1. **Mental model clarity**
   - Can you restate the desired behavior in 2–3 plain-language bullet points?
   - What is the user's expectation, independent of current code?

2. **Single authority**
   - Which component **owns** the behavior you're implementing?
   - Is there one method where the key decision is made?
   - Have you identified competing handlers that might reinterpret the same input?

3. **State ownership**
   - Where does state live? (WorkingState vs files vs cache)
   - Are you reading from the correct source of truth?
   - Check `@docs/systems/schema-and-data.md` if working with CMR/schema data.

4. **Dependency direction**
   - Does your change follow: **Input → Domain → Infrastructure**?
   - Are you creating any circular dependencies?
   - Check `@docs/reference/data-flow-patterns.md` if adding cross-component dependencies.

## Implementation Rules

### Performance (29% of historical bugs)
- **NEVER** use `Texture2D.GetPixel()` in loops → use `GetPixels()` once
- **ALWAYS** use ZLinq instead of standard LINQ in `Update()/FixedUpdate()`
- **ALWAYS** use `StringBuilder` for string building in loops
- **ALWAYS** use `*NonAlloc()` Unity methods when available
- **ALWAYS** cache frequently accessed components

### State Management (17% of historical bugs)
- **ALWAYS** read from `WorkingState`, not files
- **ALWAYS** clear temporary state between operations
- **NEVER** create duplicate state - use centralized managers
- State hierarchy: `WorkingState` → `CmrCache` → `CmrPersistent`

### Unity Lifecycle & Null References
- **NEVER** assume `Awake()` execution order - use `Start()` for cross-component init
- **NEVER** null-check `[SerializeField]` fields - let missing references crash loudly
- **NEVER** use `FindFirstObjectByType` as lazy substitute for inspector wiring
- **NEVER** use `?.` null-conditional on required dependencies
- **ALWAYS** use Script Execution Order when order matters

### Architecture (17% of historical bugs)
- **NEVER** create circular dependencies (Controller → App → Controller)
- **ALWAYS** use `On*` prefix for events, define once
- Prefer explicit, duplicated code paths over clever shared flags
- Each behavior branch should be self-contained

### Logic & Encoding
- **ALWAYS** use ABGR little-endian convention (project standard)
- **ALWAYS** use `BitOperations` utility methods for bit packing
- Check `@docs/reference/endianness.md` for encoding details

### UI/UX
- **NEVER** use hardcoded screen positions - use Layout components
- **ALWAYS** handle toggle behavior (click to open, reclick to close)
- Test at multiple aspect ratios (16:9, 16:10, 21:9, 4:3)

### Error Handling
- Include context in error messages: what went wrong, current state, expected state, how to fix
- Ensure consistent recovery behavior across failure paths

## Code Style

Follow `@AGENTS.md` conventions:

**Naming & Syntax:**
- Prefix private fields with underscore (`_variable`)
- Use target-typed `new()` expressions: `List<string> _names = new();`
- Do NOT assign redundant defaults: `int x = 0;` or `bool b = false;`
- Omit `private` when visually obvious (it's the default)
- Avoid fully qualifying namespaces covered by `using` statements

**Control Flow:**
- Early returns can be one line if short and side-effect free: `if (_isDead) return;`
- Use braces for everything except trivial single-line guards
- Loop bodies on separate lines, never: `foreach(var n in names) Debug.Log(n);`

**File Headers:**
- Add high-level description in `/* */` comments after using statements
- Leave 1 line of space before and after

```csharp
using UnityEngine;

/*
 * Manages the player's inventory state.
 * Handles serialization and UI updates.
 */

public class InventoryManager : MonoBehaviour { }
```

**Documentation:**
- Use standard `//` comments, NOT XML doc comments (`///`)

## Testing Discipline

- **NEVER** relax assertions to make tests pass - fix the underlying issue
- **NEVER** delete or skip tests that expose real issues
- **ALWAYS** run tests before considering implementation complete
- Remove diagnostic scaffolding after fixing issues
- Use `LogAssert.Expect` for expected warnings/errors
- Never use error-level logs as instrumentation (they fail tests)

## Implementation Process

1. **Identify affected files**
   - List the files you'll modify or create
   - Check for existing patterns in similar code

2. **Implement incrementally**
   - Start with the core behavior
   - Add one feature at a time
   - Verify each step works before moving on

3. **Validate**
   - Run relevant tests
   - Check for linter errors
   - Verify the behavior matches the mental model

## Non-Obvious Invariants

**Do not violate these project-specific constraints:**

- **Never paint before LUT sync is complete** — painters must read the latest schema definitions
- **Schema mutations must flow through CmrManager APIs** — do not modify schema assets at runtime directly
- **CSV exports must preserve positional ordering** — stable column indices are required for interoperability
- **CMR JSON embedding must always round-trip** — modifying JSON shape requires updating tests
- **Excel workflows depend on file watchers** — do not introduce blocking operations in ExcelBridgeQueue
- **ModelPartData render textures must not be replaced at runtime** — reuse and clear instead of reallocating

## Boundaries

✅ **Always:**
- Be compatible with No Domain/Scene Reload (reset static fields)
- Update the "Last Edited" timestamp at the top of markdown files when modifying docs

⚠️ **Ask First:**
- Before modifying 3rd party plugins

🚫 **Never:**
- Use XML documentation comments (`///`) — use standard `//` comments
- Fail silently when a null value is unexpected

## Post-Implementation Checklist

Before declaring done, verify:

- [ ] No standard LINQ in hot paths (use ZLinq)
- [ ] Using `WorkingState` not file I/O for state
- [ ] No null-checks on `[SerializeField]` fields
- [ ] No circular dependencies introduced
- [ ] Event names follow `On*` convention
- [ ] Error messages include context and solutions
- [ ] Compatible with Domain/Scene Reload (static fields reset)
- [ ] All tests pass
- [ ] No linter errors introduced

## What NOT to Do

- Don't add features beyond what was asked
- Don't refactor unrelated code
- Don't add error handling for impossible scenarios
- Don't create abstractions for one-time operations
- Don't design for hypothetical future requirements

## Tooling & CLI

When running console commands, prefer enhanced tools if available:
- `grep` / `Select-String` → `rg` (ripgrep)
- `find` / `dir` → `fd`
- `cat` / `type` → `bat`
- `ls` → `eza`

If tools are missing, run: `.\tools\setup-agent-tools.ps1`

## Style

- Be surgical: change only what's necessary
- Follow existing patterns in the codebase
- Prefer explicit over clever
- When in doubt, check the docs or ask

