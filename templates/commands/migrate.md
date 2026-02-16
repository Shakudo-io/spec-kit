---
description: Fix 1-1-1 alignment issues by migrating specs and creating worktrees.
scripts:
  sh: scripts/bash/migrate-spec.sh --dry-run --all
  ps: scripts/powershell/migrate-spec.ps1 -DryRun -All
---

## User Input

```text
$ARGUMENTS
```

## Outline

1. **Run the migration script in dry-run mode**: Execute `{SCRIPT}` to preview what changes would be made.

2. **Parse the output**: The script shows a preview of migrations:
   - Which specs will be moved from distributed to centralized location
   - Which worktrees will be created (if `--create-wt` is specified)
   - Which orphan specs need manual review

3. **Present the migration plan** to the user:

   ```
   ## Migration Plan (DRY RUN)
   
   ### Specs to Migrate (DISTRIBUTED → CENTRALIZED)
   
   | Spec | From | To |
   |------|------|-----|
   | monorepo:001-user-auth | monorepo/.specify/specs/001-user-auth/ | specs/monorepo/001-user-auth/ |
   | frontend:002-dashboard | frontend/specs/002-dashboard/ | specs/frontend/002-dashboard/ |
   
   ### Worktrees to Create (if --create-wt)
   
   | Spec | Branch | Path |
   |------|--------|------|
   | monorepo:003-api | monorepo-003-api | /root/gitrepos/monorepo-003-api/ |
   
   ### Orphan Specs (manual review)
   
   | Spec | Details |
   |------|---------|
   | legacy:old-feature | No branch found, not merged |
   ```

4. **Ask for confirmation**: Use the `question` tool to ask the user:
   - "Proceed with migration?" (Yes / No / Customize)
   - If "Customize": Ask which specific specs to migrate

5. **Execute the migration**: If confirmed, run the script with `--execute`:
   ```bash
   scripts/bash/migrate-spec.sh --execute --all --rollup
   ```

6. **Report results**:
   ```
   ## Migration Complete
   
   - **Specs migrated**: 11
   - **Worktrees created**: 2
   - **Errors**: 0
   
   The specs index has been updated. Run `/speckit.specs` to verify.
   ```

## Flags

Parse the user arguments to determine which flags to pass:

| User Says | Flags |
|-----------|-------|
| (no arguments) | `--dry-run --all` (preview all) |
| `--execute` or "do it" | `--execute --all --rollup` |
| `--create-wt` or "create worktrees" | Add `--create-wt` |
| `PROJECT:FEATURE` | Replace `--all` with specific specs |
| `--base-branch X` | Add `--base-branch X` |

## Migration Actions

| Status | Migration Action |
|--------|------------------|
| DISTRIBUTED | Move spec directory from repo to centralized `specs/PROJECT/FEATURE/` |
| MISSING_WT | Create worktree at `WORKSPACE/PROJECT-FEATURE/` for the existing branch |
| ORPHAN_SPEC | No automatic fix - present options: create branch, or archive spec |
| OK, MERGED | No action needed |

## Interactive Flow

1. **First call**: Always run dry-run first to show the plan
2. **Wait for confirmation**: Ask user to confirm before executing
3. **Execute**: Only after explicit confirmation
4. **Rollup**: Automatically update specs index after successful migration

## Examples

```text
User: /speckit.migrate
→ Run dry-run, show plan, ask for confirmation

User: /speckit.migrate --execute
→ Run dry-run, show plan, then execute with confirmation

User: /speckit.migrate monorepo:001-user-auth
→ Preview migrating only that specific spec

User: /speckit.migrate --create-wt
→ Include worktree creation in the plan

User: /speckit.migrate --base-branch dev
→ Use 'dev' instead of 'main' as base for new branches
```

## Notes

- Always show dry-run first before executing
- The `--rollup` flag is automatically added when executing to update the index
- For ORPHAN specs, guide the user through options:
  1. Create branch + worktree: "Would you like me to create a new branch for this spec?"
  2. Archive: "Would you like to move this spec to an archive location?"
- Migration preserves all spec contents (spec.md, plan.md, tasks.md, etc.)
- After migration, the spec is accessible via `project:feature` format
