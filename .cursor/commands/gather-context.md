# gather-context

Our goal is to **select the smallest useful subset of project documentation** that gives enough context to fulfill the user's input. Do not try to solve the work itself; only identify which docs should be read.

## Context & sources

- All documentation lives under the `docs/` folder.
- Treat `@docs/index.md` as your table of contents and map of the docs.
- Assume that every doc reachable (directly or indirectly) from `@docs/index.md` is fair game.
- Prefer higher-level overview docs and "source of truth" specs over narrower or outdated notes.

## What the user provides

After this prompt, the user will provide an **input brief**. This may be:
- A short task description
- A multi-section design document
- An implementation plan with phases
- Any other batch of text that describes work to be done

Treat the entire provided text as the **scope of work** that this documentation selection must support. Do not reinterpret or narrow it beyond what is written.

If the input brief refers to a specific plan file under `docs/plan/` (for example `docs/plan/new-feature-x.md`), treat that as the **plan** this documentation selection supports.

## How to decide relevance

When scanning `@docs/index.md` and linked docs, decide for each candidate doc:

1. **Directly required?**
   - Contains requirements, contracts, workflows, constraints, or invariants that must be understood to carry out the input brief safely and correctly.

2. **Helpful but optional?**
   - Clarifies background, architecture, or conventions that may help but are not strictly necessary.

3. **Irrelevant or too broad?**
   - General project info, historical notes, or unrelated subsystems that will not materially affect the work described in the input brief.

Aim for a **minimal complete set**:
- Include everything in category (1) that applies.
- Include only the few most useful items from category (2).
- Exclude (3), even if vaguely related.

When in doubt:
- Prefer fewer docs with high signal over many docs with weak or speculative relevance.
- Prefer more specific docs over broad catch-all docs, unless the input brief itself is broad.

## How to investigate

1. Start with `@docs/index.md`:
   - Identify sections and links that clearly match the domain of the input brief (features, services, modules, workflows, APIs, etc.).

2. Follow only the most relevant branches:
   - Open linked docs that likely contain requirements, contracts, or design decisions for the relevant area.

3. Use search if needed:
   - Use project-aware tools (for example file search) to look for key terms from the input brief within `docs/`.

4. De-duplicate:
   - If two docs cover the same information at different levels, pick the one that is:
     - Newer and/or clearly maintained.
     - More concise and closer to the current project reality.

## Chat output format

Respond in Markdown in chat with this structure:

1. **Input interpretation (2–4 sentences)**
   - Restate the input brief in your own words.
   - Explicitly name the main subsystem(s), feature(s), or API(s) involved.

2. **Must-read docs (minimal set)**
   - Short bullet list (aim for 1–7 items).
   - Format: `- @docs/path/to/doc.md - why this is required for the work.`
   - Include only docs that are truly necessary to execute the input brief correctly.

3. **Nice-to-have docs (optional)**
   - Bullet list (0–5 items).
   - Same format, but these are background or deep-dive references.
   - If the input brief is simple and the must-read list is enough, say `None`.

4. **Not included but considered**
   - 1–5 bullets for docs or sections you intentionally excluded.
   - Format: `- @docs/path/or/section - related but excluded because <reason>.`
   - This shows you made a deliberate minimality choice.

5. **If information seems missing**
   - If the work clearly depends on documentation that does not exist or is not discoverable via `@docs/index.md`, say what is missing and what kind of doc should exist (for example "No clear API contract doc for X").

## File output

In addition to the chat response, **write out a Markdown file under `docs/plan/`** that records the minimal context set.

1. Determine the plan name:
   - If the input brief specifies a plan file under `docs/plan/` (for example `docs/plan/new-feature-x.md`), let `<plan_basename>` be that filename without the `.md` extension (here it would be `new-feature-x`).
   - If no explicit plan file is mentioned, infer a short plan name from the input brief (kebab-case, for example "User profile sync" becomes `user-profile-sync`) and use that as `<plan_basename>`.

2. Create or overwrite:
   - Create (or overwrite) a file at:  
     `docs/plan/<plan_basename>.context.md`

3. File contents:
   - Start with a heading:  
     `# Context docs for <plan_basename>`
   - Then a section:  
     `## Must-read docs (minimal set)`  
     followed by a Markdown list of the must-read docs only, one per line, using this format:  
     `- @docs/path/to/doc.md - short reason it is required`
   - Optionally add a `## Nice-to-have docs` section with a similar list if there are any. If there are none, you can omit this section.

This file is the persistent index of documentation required to work on that plan. Keep it minimal and aligned with the Must-read docs from the chat output.

## Style

- Be concise and concrete.
- Prefer precision over breadth.
- Do not paraphrase the content of the docs; just justify why each doc is relevant or excluded.
- Do not generate or edit code or the plan itself. Only curate documentation and write the corresponding `docs/plan/*.context.md` file.
