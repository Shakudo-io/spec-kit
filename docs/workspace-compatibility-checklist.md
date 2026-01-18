# Workspace & 1-1-1 Compatibility Checklist

**Purpose**: Track adaptations needed to make spec-kit fully compatible with global workspace mode and the 1-1-1 alignment invariant.

**Last Updated**: 2026-01-18

---

## 1-1-1 Alignment Invariant

Every feature MUST have exactly:
- **ONE branch**: `{project}-{NNN}-{feature}`
- **ONE worktree**: `{workspace_root}/{project}-{NNN}-{feature}/`
- **ONE spec folder**: `{specs_dir}/{project}/{NNN}-{feature}/`

## Variable Naming Convention

| Variable | Purpose | Used For |
|----------|---------|----------|
| `SPEC_DIR` | Where spec documents live | Reading spec.md, plan.md, tasks.md, research.md |
| `SOURCE_DIR` | Where source code lives | Writing code, running tests |
| `CONSTITUTION_PATH` | Resolved constitution path | Reading constitution based on workspace.yaml |
| `FEATURE_DIR` | **LEGACY** - avoid in workspace mode | Only for backward compatibility |

---

## HIGH Priority - Variable Naming Fixes

- [x] `templates/commands/plan.md` - Updated to use `SPEC_DIR`/`SOURCE_DIR`
- [x] `templates/commands/tasks.md` - Updated to use `SPEC_DIR`/`SOURCE_DIR`
- [x] `templates/commands/implement.md` - Updated to use `SPEC_DIR`/`SOURCE_DIR`
- [x] `templates/commands/constitution.md` - Updated to use `CONSTITUTION_PATH`
- [x] `templates/commands/analyze.md` - Updated to use `CONSTITUTION_PATH` and `SPEC_DIR`
- [x] `templates/commands/clarify.md:37` - Updated to use `SPEC_DIR`
- [x] `templates/commands/checklist.md:47,89,101` - Updated to use `SPEC_DIR`
- [x] `templates/commands/taskstoissues.md:19` - Updated to use `SPEC_DIR`
- [x] `templates/commands/specify.md:120` - Updated to use `SPEC_DIR/checklists/`

## MEDIUM Priority - Documentation/Path References

- [x] `templates/commands/specify.md:67` - Updated to reference `{specs_dir}` from workspace.yaml
- [x] `templates/commands/rollup.md:63` - Updated to reference `specs_dir` from workspace.yaml

## LOW Priority - Script Hardening

- [ ] `scripts/bash/common.sh:805,819` - Branch regex `^([a-z0-9_-]+)-[0-9]{3}-` might misidentify projects with hyphens in their names
- [ ] `scripts/bash/create-new-feature.sh:411` - `SPEC_DIR_NAME` set separately from `BRANCH_NAME`; in 1-1-1 these should match exactly

## Constitution Path Resolution

- [x] `scripts/bash/common.sh` - Added `get_constitution_path()` function
- [x] `scripts/bash/check-prerequisites.sh` - Added `CONSTITUTION_PATH` to JSON output
- [x] `templates/commands/plan.md` - Uses `CONSTITUTION_PATH` from JSON
- [x] `templates/commands/constitution.md` - Uses resolved constitution path
- [x] `templates/commands/analyze.md` - Uses `CONSTITUTION_PATH` from JSON

---

## Testing Checklist

After making changes, verify:

1. [ ] `get_constitution_path` returns correct path based on `workspace.yaml`
2. [ ] `check-prerequisites.sh --json` includes `CONSTITUTION_PATH` and `SPEC_DIR`
3. [ ] All slash commands read specs from `SPEC_DIR`
4. [ ] All slash commands write code to `SOURCE_DIR`
5. [ ] Feature shorthand `project:NNN-feature` resolves correctly
6. [ ] Legacy shorthand `project-NNN` still works for backward compatibility
