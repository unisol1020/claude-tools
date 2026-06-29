## Code Comments

- **No comments by default.** Code must be self-explanatory through clear naming and structure — most files should have zero comments.
- **The only acceptable comment is a single-line `why`** that cannot be expressed in code: a non-obvious business rule, a workaround for a known bug/constraint, or a deliberate choice that looks wrong. If renaming or extracting makes it obvious, do that instead of commenting.
- **One line, hard cap.** No multi-line comment blocks. Never narrate what the code does, describe the navigation/render/data flow, restate types or control flow, or recount a refactor's history ("mirrors the old…", "this replaces…", "wraps the step content with…"). That is slop — delete it. If an explanation genuinely needs more than one line, it belongs in `apps/docs`, not inline.
- No JSDoc. No `// step 1` / `// step 2`. No banner / section-divider comments.
- Delete dead code; never comment it out.
- **When editing a file, remove any existing comment that violates these rules** — comment cleanup is part of the change.
