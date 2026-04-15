# Spec-Kit Scripting API

This document explains how to use Spec-Kit functionality programmatically via bash scripts, enabling automation, CI/CD integration, and custom tooling.

## Overview

Spec-Kit provides a bash scripting API through two main files:

| File | Purpose |
|------|---------|
| `scripts/bash/common.sh` | Core functions for workspace detection, project management, and spec resolution |
| `scripts/bash/check-prerequisites.sh` | CLI tool for querying workspace state and validating prerequisites |

## Quick Start

```bash
# Source the common functions
source .specify/scripts/bash/common.sh

# Check if in workspace mode
if is_workspace_mode; then
    echo "Workspace root: $(get_workspace_root)"
    echo "Projects: $(list_projects)"
fi
```

---

## Workspace Detection

### `is_workspace_mode`

Returns true if running inside a multi-repo workspace (has `workspace.yaml`).

```bash
if is_workspace_mode; then
    echo "Multi-repo workspace detected"
else
    echo "Legacy single-repo mode"
fi
```

### `get_workspace_root`

Returns the absolute path to the workspace root directory.

```bash
workspace=$(get_workspace_root)
echo "Workspace at: $workspace"
```

### `get_workspace_config_file`

Returns the path to `workspace.yaml`.

```bash
config_file=$(get_workspace_config_file)
cat "$config_file"
```

---

## Configuration

### `get_workspace_config`

Read a scalar value from `workspace.yaml`.

```bash
# Usage: get_workspace_config "key" [default]
strategy=$(get_workspace_config "spec_strategy" "centralized")
echo "Spec strategy: $strategy"

# Read nested keys (dot notation not supported - use flat keys)
behavior=$(get_workspace_config "no_project_behavior" "error")
```

### `get_workspace_config_list`

Read a YAML list from `workspace.yaml`. Returns one item per line.

```bash
# Get archived projects
archived=$(get_workspace_config_list "archived_projects")
while IFS= read -r project; do
    echo "Archived: $project"
done <<< "$archived"
```

---

## Project Management

### `list_projects`

List all active projects in the workspace. Excludes archived projects by default.

```bash
# List active projects only
for project in $(list_projects); do
    echo "Project: $project"
done

# Include archived projects
for project in $(list_projects --include-archived); do
    echo "Project (all): $project"
done
```

### `list_projects_detailed`

List projects with git metadata. Raw records use `SPECIFY_INTERNAL_FIELD_SEPARATOR` (ASCII unit separator) so empty metadata fields stay aligned.

```bash
# Fields: name, has_git, remote_url, branch, is_worktree, main_worktree
while IFS="$SPECIFY_INTERNAL_FIELD_SEPARATOR" read -r name has_git remote_url branch is_worktree main_worktree; do
    echo "$name: branch=$branch, git=$has_git"
done < <(list_projects_detailed)

# Include archived
list_projects_detailed --include-archived
```

### `is_project_archived`

Check if a project is in the archived list.

```bash
if is_project_archived "old-backend"; then
    echo "Project is archived"
fi
```

### `get_project_name`

Get the current project name from environment or directory.

```bash
project=$(get_project_name)
echo "Current project: $project"
```

### `get_project_root`

Get the absolute path to a project's root directory.

```bash
project_path=$(get_project_root)
echo "Project at: $project_path"
```

---

## Specs Directory

### `get_specs_dir`

Get the path to the specs directory (centralized or distributed based on config).

```bash
specs_dir=$(get_specs_dir)
echo "Specs stored at: $specs_dir"

# For centralized: /workspace/specs
# For distributed: /workspace/project/specs
```

---

## Feature Management

### `parse_feature_shorthand`

Parse a feature shorthand (e.g., `myrepo-001`) into components.

```bash
# Returns eval-able output with:
# - SHORTHAND_PROJECT: project name
# - SHORTHAND_FEATURE_NUM: feature number (e.g., "001")
# - SHORTHAND_FEATURE_NAME: full feature name (e.g., "001-user-auth")
# - SHORTHAND_FEATURE_DIR: absolute path to feature spec directory

result=$(parse_feature_shorthand "myrepo-001")
eval "$result"

echo "Project: $SHORTHAND_PROJECT"
echo "Feature: $SHORTHAND_FEATURE_NAME"
echo "Spec dir: $SHORTHAND_FEATURE_DIR"
```

### `resolve_source_dir`

Resolve where code changes should be made for a feature (worktree vs main checkout).

```bash
# Returns eval-able output with:
# - SOURCE_DIR: where to make code changes
# - SOURCE_BRANCH: current branch at that location
# - IS_WORKTREE: "true" or "false"
# - EXPECTED_BRANCH: branch the feature expects
# - BRANCH_STATUS: "ok" or "switch_needed"

result=$(resolve_source_dir "myrepo" "001-user-auth")
eval "$result"

echo "Make changes in: $SOURCE_DIR"
echo "Current branch: $SOURCE_BRANCH"
if [[ "$IS_WORKTREE" == "true" ]]; then
    echo "This is a git worktree"
fi
if [[ "$BRANCH_STATUS" == "switch_needed" ]]; then
    echo "Warning: Need to switch to branch $EXPECTED_BRANCH"
fi
```

### `resolve_source_dir_json`

Same as above but returns JSON for easier parsing.

```bash
json=$(resolve_source_dir_json "myrepo" "001-user-auth")
echo "$json" | jq '.source_dir'
```

### `get_next_workspace_feature_number`

Get the next available feature number for a project.

```bash
next_num=$(get_next_workspace_feature_number "myrepo")
echo "Next feature will be: $next_num"  # e.g., "007"
```

---

## CLI Tool: check-prerequisites.sh

The `check-prerequisites.sh` script provides a CLI interface for common operations.

### Workspace Information

```bash
# Get full workspace context as JSON
.specify/scripts/bash/check-prerequisites.sh --workspace-info

# Output:
# {
#   "workspace_mode": true,
#   "workspace_root": "/path/to/workspace",
#   "projects": [{"name": "repo-a", "source_dir": "/path/to/repo-a"}, ...],
#   "features": [{"shorthand": "repo-a-001", "source_dir": "...", ...}, ...]
# }
```

### List Projects

```bash
# Simple list
.specify/scripts/bash/check-prerequisites.sh --list-projects

# JSON format
.specify/scripts/bash/check-prerequisites.sh --list-projects --json

# Detailed with git info
.specify/scripts/bash/check-prerequisites.sh --list-projects-detailed --json
```

### List Features

```bash
# List all feature shorthands
.specify/scripts/bash/check-prerequisites.sh --list-features

# JSON format
.specify/scripts/bash/check-prerequisites.sh --list-features --json
```

### Feature Prerequisites

```bash
# Check prerequisites for a specific feature
.specify/scripts/bash/check-prerequisites.sh --json myrepo-001

# Output includes:
# - SPEC_DIR: where specs are stored
# - SOURCE_DIR: where code changes go
# - FEATURE_SPEC: path to spec.md
# - IMPL_PLAN: path to plan.md
# - TASKS: path to tasks.md
# - BRANCH_STATUS: whether branch switch is needed

# Require tasks.md to exist (for implementation phase)
.specify/scripts/bash/check-prerequisites.sh --json --require-tasks myrepo-001
```

### Spec Rollup

```bash
# Generate specs index
.specify/scripts/bash/check-prerequisites.sh --rollup

# List all specs from index
.specify/scripts/bash/check-prerequisites.sh --list-specs --json
```

---

## Common Patterns

### Iterate Over All Features

```bash
source .specify/scripts/bash/common.sh

specs_dir=$(get_specs_dir)
for project_dir in "$specs_dir"/*/; do
    project=$(basename "$project_dir")
    
    for feature_dir in "$project_dir"/*/; do
        feature=$(basename "$feature_dir")
        
        # Check if spec.md exists
        if [[ -f "$feature_dir/spec.md" ]]; then
            echo "Found spec: $project/$feature"
        fi
    done
done
```

### Find Features Missing Tasks

```bash
source .specify/scripts/bash/common.sh

specs_dir=$(get_specs_dir)
for project_dir in "$specs_dir"/*/; do
    project=$(basename "$project_dir")
    
    for feature_dir in "$project_dir"/*/; do
        if [[ -f "$feature_dir/plan.md" ]] && [[ ! -f "$feature_dir/tasks.md" ]]; then
            echo "Missing tasks: $project/$(basename "$feature_dir")"
        fi
    done
done
```

### CI/CD Integration

```bash
#!/bin/bash
# Example: Validate all specs have required files

source .specify/scripts/bash/common.sh

exit_code=0
specs_dir=$(get_specs_dir)

for project_dir in "$specs_dir"/*/; do
    project=$(basename "$project_dir")
    
    for feature_dir in "$project_dir"/*/; do
        feature=$(basename "$feature_dir")
        
        # Require spec.md
        if [[ ! -f "$feature_dir/spec.md" ]]; then
            echo "ERROR: Missing spec.md in $project/$feature"
            exit_code=1
        fi
        
        # If plan.md exists, require tasks.md
        if [[ -f "$feature_dir/plan.md" ]] && [[ ! -f "$feature_dir/tasks.md" ]]; then
            echo "WARNING: $project/$feature has plan but no tasks"
        fi
    done
done

exit $exit_code
```

### Custom Workspace Report

```bash
#!/bin/bash
# Generate a markdown report of workspace status

source .specify/scripts/bash/common.sh

echo "# Workspace Report"
echo ""
echo "**Generated**: $(date)"
echo "**Root**: $(get_workspace_root)"
echo ""

echo "## Projects"
echo ""
echo "| Project | Archived | Features |"
echo "|---------|----------|----------|"

for project in $(list_projects --include-archived); do
    archived="No"
    if is_project_archived "$project"; then
        archived="Yes"
    fi
    
    specs_dir=$(get_specs_dir)
    feature_count=$(ls -d "$specs_dir/$project"/*/ 2>/dev/null | wc -l)
    
    echo "| $project | $archived | $feature_count |"
done
```

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `SPECIFY_WORKSPACE` | Override workspace root detection |
| `SPECIFY_PROJECT` | Set current project explicitly |
| `SPECIFY_FEATURE` | Set current feature explicitly |

```bash
# Force a specific workspace root
export SPECIFY_WORKSPACE=/path/to/workspace
source .specify/scripts/bash/common.sh

# Work with a specific project
export SPECIFY_PROJECT=backend-api
project_root=$(get_project_root)
```

---

## Error Handling

Most functions return non-zero exit codes on failure. Use standard bash error handling:

```bash
source .specify/scripts/bash/common.sh

# Check for errors
if ! workspace_root=$(get_workspace_root); then
    echo "Not in a workspace" >&2
    exit 1
fi

# Or use set -e for automatic exit on error
set -e
workspace_root=$(get_workspace_root)
specs_dir=$(get_specs_dir)
```

---

## See Also

- [Workspace Setup](./workspace-spec-rollup-plan.md) - Multi-repo workspace configuration
- [Upgrade Guide](./upgrade.md) - Updating Spec-Kit versions
- [README](../README.md) - Slash commands and AI agent usage
