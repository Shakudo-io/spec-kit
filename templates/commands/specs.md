---
description: List all specs across the workspace from the index.
scripts:
  sh: scripts/bash/check-prerequisites.sh --list-specs --json
  ps: scripts/powershell/check-prerequisites.ps1 -ListSpecs -Json
---

## User Input

```text
$ARGUMENTS
```

## Outline

1. **Run the script**: Execute `{SCRIPT}` from the workspace root to list all indexed specs.

2. **Parse the JSON output**: The script returns the same format as `/speckit.rollup`:
   - `version`: Index format version
   - `workspace_root`: The absolute path to the workspace
   - `generated_at`: Timestamp of index generation
   - `spec_count`: Total number of specs found
   - `specs`: Array of spec objects with full metadata

3. **Display the results**: Format and display the specs in a clear table:

   ```
   ## Workspace Specs
   
   **Workspace**: /path/to/workspace
   **Total specs**: 12
   
   | Project | Feature | Spec | Plan | Tasks | Branch |
   |---------|---------|------|------|-------|--------|
   | backend-api | 001-auth-system | ✓ | ✓ | ✓ | main |
   | backend-api | 002-rate-limiting | ✓ | ✓ | - | main |
   | frontend | 001-dashboard | ✓ | - | - | develop |
   ```

4. **Handle user queries**: If the user asks about specific specs:
   - Filter by project name
   - Filter by completion status (has plan, has tasks)
   - Show details for a specific spec using `project:feature` format

5. **Handle edge cases**:
   - If not in workspace mode, inform the user to initialize with `specify workspace --here`
   - If index is missing, it will be auto-generated
   - If no specs found, suggest creating specs with `/speckit.specify`

## Flags

- `--force-refresh`: Regenerate the index before listing
- `--include-worktrees`: Include specs from git worktrees
- `--json`: Output raw JSON instead of formatted table

## Working with Specs

To work on a specific spec from this list:

```bash
/speckit.plan project:feature      # Create/update implementation plan
/speckit.tasks project:feature     # Generate task breakdown
/speckit.implement project:feature # Execute implementation
```

## Notes

- The index is automatically refreshed if missing
- Use `--force-refresh` to ensure the index is up-to-date
- Worktrees are deduplicated by default (same repo = indexed once)
- Use `/speckit.rollup` to manually regenerate the index
