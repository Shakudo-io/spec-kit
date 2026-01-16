# Workspace Spec Rollup - Implementation Plan

> **Status:** Planning  
> **Created:** 2026-01-16  
> **Author:** AI Assistant  

## Overview

Enable management of specs, plans, and task lists at the workspace level while incorporating existing spec content from project subfolders (repos and worktrees).

### Design Principles

1. **Specs stay in place** - No moving/copying, specs remain in their project folders
2. **Workspace as control plane** - Unified access point for all spec operations
3. **Index as lookup table** - Fast access via `specs-index.json`, with auto-refresh on miss
4. **Worktree deduplication** - Show specs once even if multiple worktrees exist for same repo

---

## Architecture

### File Structure

```
<workspace>/
  .specify/
    workspace.yaml           # Existing workspace marker
    specs-index.json         # Auto-generated index of all specs
    specs-index.md           # Human-readable summary
    specs/                   # Optional: workspace-level specs
  
  <project-a>/
    .specify/specs/
      001-feature/
        spec.md
        plan.md
        tasks.md
  
  <worktree-of-project-a>/   # Shares same repo as project-a
    .specify/specs/          # Same specs (will be deduped)
```

### Index Schema (`specs-index.json`)

```json
{
  "version": "1.0",
  "workspace_root": "/root/gitrepos",
  "generated_at": "2026-01-16T10:00:00Z",
  "specs": [
    {
      "id": "monorepo:001-cost-estimation",
      "project": "monorepo",
      "feature": "001-cost-estimation",
      "spec_path": "monorepo/.specify/specs/001-cost-estimation/spec.md",
      "plan_path": "monorepo/.specify/specs/001-cost-estimation/plan.md",
      "tasks_path": "monorepo/.specify/specs/001-cost-estimation/tasks.md",
      "has_spec": true,
      "has_plan": true,
      "has_tasks": true,
      "repo_url": "git@github.com:devsentient/monorepo.git",
      "branch": "feat/cost-estimation",
      "is_worktree": false,
      "last_modified": "2026-01-15T14:30:00Z"
    }
  ],
  "deduped_worktrees": [
    {
      "worktree": "monorepo-feat-cost-estimation",
      "canonical": "monorepo",
      "reason": "worktree of same repo"
    }
  ]
}
```

### Command Syntax

```bash
# From workspace root:
/speckit.rollup                              # Scan and build index
/speckit.specs                               # List all indexed specs
/speckit.plan monorepo:001-cost-estimation   # Run plan on specific spec
/speckit.tasks monorepo:001-cost-estimation  # Generate tasks for spec
/speckit.implement monorepo:001-cost-estimation  # Implement spec
```

---

## Implementation Checklist

### Phase 1: Core Infrastructure

#### 1.1 Spec Discovery Functions (bash)
- [ ] Add `scan_project_for_specs()` function to `scripts/bash/common.sh`
  - Scan a single project directory for `.specify/specs/` or `specs/` folders
  - Return list of features found with metadata
- [ ] Add `scan_workspace_specs()` function to `scripts/bash/common.sh`
  - Iterate over all projects in workspace
  - Call `scan_project_for_specs()` for each
  - Handle worktree deduplication (skip if same repo URL already indexed)
- [ ] Add `get_spec_metadata()` function
  - Check existence of spec.md, plan.md, tasks.md
  - Get last modified timestamp
  - Extract status if available

#### 1.2 Spec Discovery Functions (PowerShell)
- [ ] Add `Get-ProjectSpecs` function to `scripts/powershell/common.ps1`
- [ ] Add `Get-WorkspaceSpecs` function to `scripts/powershell/common.ps1`
- [ ] Add `Get-SpecMetadata` function

#### 1.3 Index Management Functions (bash)
- [ ] Add `generate_specs_index()` function
  - Call `scan_workspace_specs()`
  - Output JSON to `.specify/specs-index.json`
  - Output Markdown to `.specify/specs-index.md`
- [ ] Add `read_specs_index()` function
  - Parse `specs-index.json`
  - Return spec list
- [ ] Add `resolve_spec_path()` function
  - Input: `project:feature` identifier
  - Lookup in index
  - If not found or path doesn't exist, trigger auto-refresh
  - Return resolved absolute path

#### 1.4 Index Management Functions (PowerShell)
- [ ] Add `New-SpecsIndex` function
- [ ] Add `Read-SpecsIndex` function
- [ ] Add `Resolve-SpecPath` function

#### 1.5 Live Testing - Phase 1
> **Test environment:** `/root/gitrepos` workspace (has repos, worktrees, some with specs)

- [ ] **Test `scan_project_for_specs()`**
  ```bash
  # Copy updated common.sh to workspace, then:
  source .specify/scripts/bash/common.sh
  scan_project_for_specs "/root/gitrepos/monorepo"
  scan_project_for_specs "/root/gitrepos/business-automation"
  ```
  - Verify: Returns feature list with correct paths
  - Verify: Handles projects without specs gracefully

- [ ] **Test `scan_workspace_specs()`**
  ```bash
  scan_workspace_specs
  ```
  - Verify: Finds specs across multiple projects
  - Verify: Worktree deduplication works (same repo URL = skip)

- [ ] **Test `generate_specs_index()`**
  ```bash
  generate_specs_index
  cat .specify/specs-index.json | jq .
  cat .specify/specs-index.md
  ```
  - Verify: JSON is valid and contains expected fields
  - Verify: Markdown is human-readable

- [ ] **Test `resolve_spec_path()`**
  ```bash
  resolve_spec_path "monorepo:001-feature"
  ```
  - Verify: Returns correct absolute path
  - Verify: Returns error for non-existent spec

### Phase 2: New Commands

#### 2.1 `/speckit.rollup` Command
- [ ] Create `templates/commands/rollup.md` template
  - Description and usage
  - Invoke rollup script
- [ ] Add `--rollup` flag to `scripts/bash/check-prerequisites.sh`
  - Call `generate_specs_index()`
  - Output success message with count of specs found
- [ ] Add `--rollup` flag to `scripts/powershell/check-prerequisites.ps1`
- [ ] Add `--json` support for rollup output
- [ ] Handle edge cases:
  - [ ] Empty workspace (no projects with specs)
  - [ ] Projects with no specs
  - [ ] Corrupted/incomplete spec folders
  - [ ] Permission errors

#### 2.2 `/speckit.specs` Command
- [ ] Create `templates/commands/specs.md` template
- [ ] Add `--list-specs` flag to `scripts/bash/check-prerequisites.sh`
  - Read from index
  - Display table: PROJECT | FEATURE | STATUS | SPEC | PLAN | TASKS
  - Auto-refresh index if missing or stale
- [ ] Add `--list-specs` flag to `scripts/powershell/check-prerequisites.ps1`
- [ ] Add `--json` support for specs listing
- [ ] Add filtering options:
  - [ ] `--project <name>` - filter by project
  - [ ] `--has-plan` / `--no-plan` - filter by plan existence
  - [ ] `--has-tasks` / `--no-tasks` - filter by tasks existence

#### 2.3 Live Testing - Phase 2
> **Non-destructive:** These commands only read/index, never modify specs

- [ ] **Test `/speckit.rollup` (via script flag)**
  ```bash
  cd /root/gitrepos
  ./.specify/scripts/bash/check-prerequisites.sh --rollup
  ```
  - Verify: Creates `.specify/specs-index.json`
  - Verify: Creates `.specify/specs-index.md`
  - Verify: Output shows count of specs found
  - Verify: Running twice produces same result (idempotent)

- [ ] **Test `/speckit.rollup --json`**
  ```bash
  ./.specify/scripts/bash/check-prerequisites.sh --rollup --json
  ```
  - Verify: Outputs valid JSON to stdout

- [ ] **Test `/speckit.specs` (via script flag)**
  ```bash
  ./.specify/scripts/bash/check-prerequisites.sh --list-specs
  ```
  - Verify: Shows table with PROJECT | FEATURE | SPEC | PLAN | TASKS columns
  - Verify: Auto-refreshes if index missing (delete index, run again)

- [ ] **Test edge cases**
  ```bash
  # Empty/new workspace
  mkdir /tmp/test-workspace && cd /tmp/test-workspace
  specify workspace --here
  ./.specify/scripts/bash/check-prerequisites.sh --rollup
  # Should succeed with 0 specs
  ```

### Phase 3: Update Existing Commands

#### 3.1 Update `/speckit.plan`
- [ ] Modify `templates/commands/plan.md`
  - Accept optional `project:feature` argument
  - Document workspace-level usage
- [ ] Update plan script to handle workspace context:
  - [ ] If `project:feature` provided, resolve via index
  - [ ] Change to project directory before executing
  - [ ] Update index after plan creation

#### 3.2 Update `/speckit.tasks`
- [ ] Modify `templates/commands/tasks.md`
  - Accept optional `project:feature` argument
- [ ] Update tasks script for workspace context

#### 3.3 Update `/speckit.implement`
- [ ] Modify `templates/commands/implement.md`
  - Accept optional `project:feature` argument
- [ ] Update implement script for workspace context

#### 3.4 Update `/speckit.specify`
- [ ] Modify `templates/commands/specify.md`
  - Accept optional `--project` argument for workspace-level spec creation
- [ ] Update specify script:
  - [ ] If at workspace level with `--project`, create spec in that project
  - [ ] Update index after spec creation

#### 3.5 Live Testing - Phase 3
> **Test with disposable test spec** to avoid modifying real specs

- [ ] **Setup test project with spec**
  ```bash
  cd /root/gitrepos
  mkdir -p test-rollup-project/.specify/specs/001-test-feature
  echo "# Test Spec" > test-rollup-project/.specify/specs/001-test-feature/spec.md
  git -C test-rollup-project init
  ./.specify/scripts/bash/check-prerequisites.sh --rollup
  ```

- [ ] **Test `project:feature` resolution**
  ```bash
  # Verify the spec appears in index
  ./.specify/scripts/bash/check-prerequisites.sh --list-specs | grep test-rollup-project
  ```

- [ ] **Test command targeting (read-only first)**
  ```bash
  # Test that resolve_spec_path works from workspace level
  source .specify/scripts/bash/common.sh
  resolve_spec_path "test-rollup-project:001-test-feature"
  # Should return: /root/gitrepos/test-rollup-project/.specify/specs/001-test-feature
  ```

- [ ] **Cleanup test project**
  ```bash
  rm -rf /root/gitrepos/test-rollup-project
  ./.specify/scripts/bash/check-prerequisites.sh --rollup  # Re-index
  ```

### Phase 4: Auto-Refresh & Staleness

#### 4.1 Staleness Detection
- [ ] Add `is_index_stale()` function
  - Compare index timestamp with newest spec file modification
  - Return true if any spec file is newer than index
- [ ] Add `--force-refresh` flag to commands
  - Always regenerate index before operation

#### 4.2 Auto-Refresh Integration
- [ ] Modify `resolve_spec_path()` to auto-refresh on:
  - [ ] Index file missing
  - [ ] Requested spec not in index
  - [ ] Spec path in index doesn't exist on filesystem
- [ ] Add warning message when auto-refresh occurs
- [ ] Add `--no-auto-refresh` flag to disable

#### 4.3 Live Testing - Phase 4
> **Test auto-refresh behavior**

- [ ] **Test missing index auto-refresh**
  ```bash
  cd /root/gitrepos
  rm .specify/specs-index.json
  source .specify/scripts/bash/common.sh
  resolve_spec_path "monorepo:001-feature"  # Should auto-refresh and find
  ls .specify/specs-index.json  # Should exist again
  ```

- [ ] **Test stale index detection**
  ```bash
  # Create a new spec after index was generated
  mkdir -p test-stale/.specify/specs/001-new
  echo "# New" > test-stale/.specify/specs/001-new/spec.md
  git -C test-stale init
  
  # Try to resolve - should trigger refresh
  resolve_spec_path "test-stale:001-new"
  
  # Cleanup
  rm -rf test-stale
  ```

- [ ] **Test --force-refresh flag**
  ```bash
  ./.specify/scripts/bash/check-prerequisites.sh --list-specs --force-refresh
  ```
  - Verify: Index is regenerated even if not stale

### Phase 5: Worktree Handling

#### 5.1 Deduplication Logic
- [ ] Implement deduplication in `scan_workspace_specs()`
  - Track seen repo URLs
  - Skip worktrees if main repo already indexed
  - Record skipped worktrees in `deduped_worktrees` array
- [ ] Add `--include-worktrees` flag to include all (no dedup)
- [ ] Prefer main worktree over branch worktrees when deduping

#### 5.2 Worktree-Specific Features
- [ ] Show worktree info in `/speckit.specs` output when relevant
- [ ] Allow targeting specific worktree with explicit path if needed

#### 5.3 Live Testing - Phase 5
> **Test with actual worktrees in `/root/gitrepos`**

- [ ] **Verify worktree deduplication**
  ```bash
  cd /root/gitrepos
  ./.specify/scripts/bash/check-prerequisites.sh --rollup --json | jq '.deduped_worktrees'
  ```
  - Verify: `monorepo-feat-*` worktrees are listed as deduped
  - Verify: `business-automation-*` worktrees are listed as deduped
  - Verify: Main repos (`monorepo`, `business-automation`) have their specs indexed

- [ ] **Verify specs only appear once**
  ```bash
  ./.specify/scripts/bash/check-prerequisites.sh --list-specs | grep monorepo
  ```
  - Verify: Each spec appears once, not duplicated across worktrees

- [ ] **Test --include-worktrees flag**
  ```bash
  ./.specify/scripts/bash/check-prerequisites.sh --rollup --include-worktrees
  ./.specify/scripts/bash/check-prerequisites.sh --list-specs
  ```
  - Verify: Now shows specs from worktrees too (with worktree indicator)

### Phase 6: Documentation & Final Validation

#### 6.1 Documentation
- [ ] Update README.md with workspace-level commands
- [ ] Add workspace workflow section to docs
- [ ] Document `project:feature` syntax
- [ ] Add examples for multi-repo workspace scenarios

#### 6.2 Final Integration Testing
> **End-to-end workflow validation**

- [ ] **Full workflow test**
  ```bash
  cd /root/gitrepos
  
  # 1. Fresh rollup
  rm -f .specify/specs-index.json .specify/specs-index.md
  ./.specify/scripts/bash/check-prerequisites.sh --rollup
  
  # 2. List all specs
  ./.specify/scripts/bash/check-prerequisites.sh --list-specs
  
  # 3. Get JSON output
  ./.specify/scripts/bash/check-prerequisites.sh --list-specs --json | jq '.specs | length'
  
  # 4. Filter by project
  ./.specify/scripts/bash/check-prerequisites.sh --list-specs --project monorepo
  ```

- [ ] **Cross-platform validation (if PowerShell available)**
  ```powershell
  cd /root/gitrepos
  ./.specify/scripts/powershell/check-prerequisites.ps1 -Rollup
  ./.specify/scripts/powershell/check-prerequisites.ps1 -ListSpecs
  ```

- [ ] **Verify no regressions in existing functionality**
  ```bash
  # Existing commands should still work
  ./.specify/scripts/bash/check-prerequisites.sh --list-projects
  ./.specify/scripts/bash/check-prerequisites.sh --list-projects-detailed
  ./.specify/scripts/bash/check-prerequisites.sh --list-features --project spec-kit
  ```

- [ ] **Edge case coverage**
  - [ ] Empty workspace (no projects with specs)
  - [ ] Projects with no specs mixed with projects that have specs
  - [ ] Corrupted/incomplete spec folders
  - [ ] Very large workspace (many projects)

---

## Open Questions

1. **Workspace-level specs**: Should we support creating specs that live at workspace level (not tied to any project)? Use case: cross-project coordination specs.

2. **Index location**: Should index be in `.specify/` (current plan) or a dedicated `.specify/workspace/` folder?

3. **Status tracking**: Should we parse spec files to extract status, or keep index lightweight with just paths?

4. **Refresh strategy**: How aggressively should we auto-refresh? Options:
   - Only on miss (current plan)
   - On every command if index older than X minutes
   - Never auto (require explicit rollup)

---

## Success Criteria

- [ ] Can run `/speckit.rollup` from workspace root and see all specs indexed
- [ ] Can run `/speckit.specs` and see unified list of all specs
- [ ] Can run `/speckit.plan monorepo:001-feature` from workspace root
- [ ] Worktrees are properly deduplicated
- [ ] Auto-refresh works when spec is missing from index
- [ ] Both bash and PowerShell scripts work correctly
