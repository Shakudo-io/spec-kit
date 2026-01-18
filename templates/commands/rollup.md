---
description: Scan the workspace and generate an index of all specs across projects.
scripts:
  sh: scripts/bash/check-prerequisites.sh --rollup --json
  ps: scripts/powershell/check-prerequisites.ps1 -Rollup -Json
---

## User Input

```text
$ARGUMENTS
```

## Outline

1. **Run the script**: Execute `{SCRIPT}` from the workspace root to scan all projects for specs.

2. **Parse the JSON output**: The script returns a JSON object with:
   - `version`: Index format version
   - `workspace_root`: The absolute path to the workspace
   - `generated_at`: Timestamp of index generation
   - `spec_count`: Total number of specs found
   - `specs`: An array of spec objects, each containing:
     - `id`: Unique identifier in `project:feature` format
     - `project`: The project directory name
     - `feature`: The feature directory name
     - `spec_path`: Relative path to spec.md
     - `plan_path`: Relative path to plan.md
     - `tasks_path`: Relative path to tasks.md
     - `has_spec`: Whether spec.md exists (true/false)
     - `has_plan`: Whether plan.md exists (true/false)
     - `has_tasks`: Whether tasks.md exists (true/false)
     - `repo_url`: Git remote origin URL
     - `branch`: Current git branch
     - `is_worktree`: Whether this is a git worktree
     - `last_modified`: Unix timestamp of most recent file modification

3. **Display the results**: Confirm the rollup completed and show summary:

   ```
   ## Workspace Specs Rollup Complete
   
   **Workspace**: /path/to/workspace
   **Specs indexed**: 12
   
   Index files created:
   - `.specify/specs-index.json` (machine-readable)
   - `.specify/specs-index.md` (human-readable)
   ```

4. **Handle edge cases**:
   - If not in workspace mode, inform the user to initialize with `specify workspace --here`
   - If no specs found, suggest creating specs with `/speckit.specify`
   - Worktrees are deduplicated by default (same repo URL = indexed once)

## Flags

- `--include-worktrees`: Include specs from git worktrees (disables deduplication)
- `--json`: Output the full index as JSON instead of summary

## Notes

- The rollup scans the `specs_dir` path configured in `workspace.yaml` (defaults to `specs/` in workspace root), or `.specify/specs/` for legacy single-repo mode
- Worktrees sharing the same repository are deduplicated by default
- Use `/speckit.specs` to view the indexed specs in a table format
- The index is used by other commands to resolve `project:feature` references
