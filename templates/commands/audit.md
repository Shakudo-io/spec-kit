---
description: Audit workspace for 1-1-1 alignment between branches, worktrees, and specs.
scripts:
  sh: scripts/bash/audit-alignment.sh --no-fetch --json
  ps: scripts/powershell/audit-alignment.ps1 -NoFetch -Json
---

## User Input

```text
$ARGUMENTS
```

## Outline

1. **Run the audit script**: Execute `{SCRIPT}` from the workspace root to check all specs for 1-1-1 alignment.

2. **Parse the JSON output**: The script returns a JSON object with:
   - `workspace_root`: The absolute path to the workspace
   - `timestamp`: When the audit was run
   - `summary`: Counts by status type
     - `total`: Total specs audited
     - `ok`: Fully aligned (branch + worktree + spec)
     - `merged`: Feature was merged (branch deleted, spec retained as documentation)
     - `orphan`: Spec exists but no branch found (and not merged)
     - `missing_worktree`: Branch exists but no worktree created
     - `distributed`: Spec in repo instead of centralized location
     - `issues_found`: Total specs needing attention
   - `results`: Array of spec audit results, each containing:
     - `project`: Project name
     - `feature`: Feature name (e.g., `001-user-auth`)
     - `status`: One of `OK`, `MERGED`, `ORPHAN_SPEC`, `MISSING_WT`, `DISTRIBUTED`
     - `details`: Human-readable description of the issue
     - `spec_path`: Current spec location
     - `expected_spec_path`: Where the spec should be (for DISTRIBUTED)

3. **Display results as a table**:

   ```
   ## 1-1-1 Alignment Audit Results
   
   | Project | Feature | Status | Details |
   |---------|---------|--------|---------|
   | monorepo | 001-user-auth | ✓ OK | Branch + worktree aligned |
   | monorepo | 002-api-gateway | ⊕ MERGED | Feature merged to main |
   | frontend | 003-dashboard | ⚠ DISTRIBUTED | Needs migration to /specs/frontend/003-dashboard/ |
   
   ### Summary
   - **OK**: 5
   - **Merged**: 2
   - **Orphan**: 0
   - **Missing Worktree**: 1
   - **Distributed**: 11
   - **Total Issues**: 12
   ```

4. **Recommend actions for issues**:

   | Status | Meaning | Recommended Action |
   |--------|---------|-------------------|
   | `OK` | Fully aligned | None |
   | `MERGED` | Merged to main/dev | None (spec serves as documentation) |
   | `ORPHAN_SPEC` | No branch, not merged | Create branch+worktree, or archive the spec |
   | `MISSING_WT` | Branch exists, no worktree | Run `/speckit.migrate --create-wt` |
   | `DISTRIBUTED` | Spec in wrong location | Run `/speckit.migrate` to move to centralized location |

5. **Offer to fix issues**: If issues are found, ask the user if they want to run `/speckit.migrate` to fix them.

## Flags

- `--quiet`: Only show specs with issues (hide OK and MERGED)
- `--project NAME`: Audit only the specified project
- `--no-fetch`: Skip git fetch (faster, uses local refs only)
- `--json`: Output raw JSON (default when script is called)

## Status Explanations

### OK (✓)
The spec has a corresponding branch and worktree. The 1-1-1 invariant is maintained.

### MERGED (⊕)
The feature branch was merged to main/dev and deleted. The spec remains as documentation of what was built. This is NOT an error - it's the expected end state of completed features.

### ORPHAN_SPEC (⚠)
A spec exists but there's no corresponding branch (local or remote) AND the feature was never merged. This could mean:
- The branch was accidentally deleted
- The spec was created manually without using the proper workflow
- Action: Create a new branch/worktree, or archive the spec if it's obsolete

### MISSING_WT (⚠)
A branch exists for this feature but no worktree was created. The developer may be working in the main checkout instead of an isolated worktree.
- Action: Run `/speckit.migrate --create-wt` to create the worktree

### DISTRIBUTED (⚠)
The spec is located inside the project repository (e.g., `monorepo/.specify/specs/`) instead of the centralized specs directory (`/root/gitrepos/specs/monorepo/`).
- Action: Run `/speckit.migrate` to move specs to the centralized location

## Notes

- Audit checks git merge history to detect merged features (avoids false ORPHAN alarms)
- For squash-merged PRs, the audit searches commit messages for the branch/feature name
- Run `/speckit.rollup` after migrations to update the specs index
- The audit respects `workspace.yaml` settings for branch naming and worktree locations
