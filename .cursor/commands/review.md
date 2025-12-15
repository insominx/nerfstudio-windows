# critique
# review-design

Your goal is to **evaluate the design quality** of the selected code or described architecture. Do **not** rewrite or modify code unless the user explicitly asks for it.

## Context
- Treat `@docs/systems` as the source of truth for overall intent.
- If you need to search the codebase, follow `@ai_console_prompt.md` and its tools (e.g. `rg`, `fd`).
- Respect the project’s agent conventions in `@agents.md`.

## Scope
The user will select:
- One or more classes/modules, or
- A small set of files, or
- A description of an architecture change.

Treat that selection (plus any obviously related files) as the **current design proposal**.

## What to evaluate

Look at the design along these axes:

1. **Responsibilities & soundness**
   - Are responsibilities for each class/module cohesive and clear?
   - Are there obvious violations of separation of concerns?
   - Are unrelated reasons to change bundled together?

2. **Simplicity**
   - Is this the **simplest reasonable design** that fits the requirements?
   - Where is it over-engineered (unnecessary layers, patterns, indirection)?
   - Where is it under-engineered (everything in one place, fuzzy boundaries)?

3. **Dependencies & coupling**
   - Any circular or near-circular dependencies (import cycles, mutual references)?
   - Tight coupling, global state, or knowledge leaking across boundaries?
   - Do callers need to know internal details to use the APIs?

4. **Risks, hacks & smells**
   - “Hacky” bits: ad-hoc flags, brittle conditionals, magic constants, copy-paste logic, or comments admitting it’s a workaround.
   - Classic smells: god objects, feature envy, shotgun surgery, unnecessary singletons, misplaced responsibilities.
   - Distinguish small pragmatic shortcuts from structural problems, and mark severity: `(minor)`, `(moderate)`, `(severe)`.

5. **Change-resilience & testability**
   - Given likely future changes (names, docs, usage), where is the design fragile?
   - Where will small changes force edits across many files?
   - Are main behaviors easy to unit test in isolation, with dependencies injectable or at least swappable?

## How to investigate
- Use project-aware tools (`rg`, language server, references/implementation lookups) to:
  - See who calls what and how data flows.
  - Check for import cycles or suspicious mutual references.
- Prefer quick checks over guessing when relationships are unclear.

## Output format
Respond in Markdown with **this structure**:

1. **High-level verdict (3–5 sentences)**
   - Overall soundness.
   - Biggest strength.
   - Biggest risk or flaw.

2. **Findings by category**
   - **Responsibilities & soundness**
     - Bullet points with concrete observations (include class/module names).
   - **Simplicity**
     - Bullets where it’s too complex or too minimal, and why.
   - **Dependencies & coupling**
     - Bullets for notable couplings and any suspected or confirmed cycles.
   - **Risks, hacks & smells**
     - Each item labeled with `(minor)`, `(moderate)`, or `(severe)`.
   - **Change-resilience & testability**
     - Bullets on where changes are likely to break things and how testable it is.

3. **Ranked refactor suggestions**
   - Short numbered list of the **top 3–5 design changes**.
   - For each:
     - What to change (specific classes/modules/APIs).
     - Why it helps (e.g. simpler, less coupling, clearer responsibility, fewer hacks).
     - Rough effort: `easy` / `medium` / `hard`.

4. **If information is missing**
   - Explicitly say what you could not assess and what you would check next in the codebase.

## Style
- Be direct and concrete.
- Prefer specific, surgical improvements over generic advice.
- Do not generate or edit code unless the user explicitly requests it.
