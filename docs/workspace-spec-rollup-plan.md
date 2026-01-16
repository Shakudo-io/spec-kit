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

### Phase 6: Documentation & Testing

#### 6.1 Documentation
- [ ] Update README.md with workspace-level commands
- [ ] Add workspace workflow section to docs
- [ ] Document `project:feature` syntax
- [ ] Add examples for multi-repo workspace scenarios

#### 6.2 Testing
- [ ] Test with workspace containing:
  - [ ] Multiple independent repos
  - [ ] Repos with multiple worktrees
  - [ ] Mix of projects with and without specs
  - [ ] Nested spec directories
- [ ] Test auto-refresh scenarios
- [ ] Test edge cases (empty workspace, missing index, etc.)

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
