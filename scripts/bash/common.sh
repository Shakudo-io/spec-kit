#!/usr/bin/env bash
# Common functions and variables for all scripts
# Version: 2.0.0 - Multi-repository workspace support

# =============================================================================
# WORKSPACE DETECTION
# =============================================================================

# Find workspace root by looking for workspace.yaml upward
# Supports both scripts/bash/workspace.yaml (spec-kit structure) and .specify/workspace.yaml (installed)
get_workspace_root() {
    # Check explicit env var first
    if [[ -n "${SPECIFY_WORKSPACE:-}" ]]; then
        echo "$SPECIFY_WORKSPACE"
        return 0
    fi
    
    # Look for workspace.yaml upward from current dir
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        # Check for spec-kit structure: scripts/bash/workspace.yaml
        if [[ -f "$dir/scripts/bash/workspace.yaml" ]]; then
            echo "$dir"
            return 0
        fi
        # Check for installed structure: .specify/workspace.yaml  
        if [[ -f "$dir/.specify/workspace.yaml" ]]; then
            echo "$dir"
            return 0
        fi
        # Check for workspace.yaml at root
        if [[ -f "$dir/workspace.yaml" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    
    # No workspace found - return empty (legacy mode)
    return 1
}

# Check if we're in workspace mode (multi-repo) vs legacy mode (single-repo)
is_workspace_mode() {
    get_workspace_root >/dev/null 2>&1
}

# Get path to workspace.yaml
get_workspace_config_file() {
    local workspace_root
    if ! workspace_root=$(get_workspace_root); then
        return 1
    fi
    
    # Check all possible locations
    if [[ -f "$workspace_root/scripts/bash/workspace.yaml" ]]; then
        echo "$workspace_root/scripts/bash/workspace.yaml"
    elif [[ -f "$workspace_root/.specify/workspace.yaml" ]]; then
        echo "$workspace_root/.specify/workspace.yaml"
    elif [[ -f "$workspace_root/workspace.yaml" ]]; then
        echo "$workspace_root/workspace.yaml"
    else
        return 1
    fi
}

# Parse a value from workspace.yaml (simple grep-based parser)
# Usage: get_workspace_config "key" [default]
get_workspace_config() {
    local key="$1"
    local default="${2:-}"
    
    local config_file
    if ! config_file=$(get_workspace_config_file); then
        echo "$default"
        return
    fi
    
    # Simple YAML parser for flat keys (handles "key: value" format)
    local value
    value=$(grep "^${key}:" "$config_file" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//' | sed 's/[[:space:]]*$//' | sed 's/^["'"'"']//' | sed 's/["'"'"']$//')
    
    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# Get the centralized specs directory
get_specs_dir() {
    if is_workspace_mode; then
        local workspace_root
        workspace_root=$(get_workspace_root)
        local strategy
        strategy=$(get_workspace_config "spec_strategy" "centralized")
        
        case "$strategy" in
            centralized)
                local specs_dir
                specs_dir=$(get_workspace_config "specs_dir" "$workspace_root/specs")
                echo "$specs_dir"
                ;;
            distributed)
                # For distributed, specs are in each repo
                local project_root
                project_root=$(get_project_root) || return 1
                echo "$project_root/specs"
                ;;
            *)
                echo "$workspace_root/specs"
                ;;
        esac
    else
        # Legacy: specs in repo root
        local repo_root
        repo_root=$(get_repo_root)
        echo "$repo_root/specs"
    fi
}

# =============================================================================
# PROJECT DETECTION (Multi-repo support)
# =============================================================================

# Get project name from environment or current directory
get_project_name() {
    # Check explicit env var first
    if [[ -n "${SPECIFY_PROJECT:-}" ]]; then
        echo "$SPECIFY_PROJECT"
        return 0
    fi
    
    # If in a git repo, extract project name from repo path
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
        local repo_root
        repo_root=$(git rev-parse --show-toplevel)
        basename "$repo_root"
        return 0
    fi
    
    # Check if we're in workspace mode and require explicit project
    if is_workspace_mode; then
        local behavior
        behavior=$(get_workspace_config "no_project_behavior" "error")
        
        case "$behavior" in
            error)
                echo "ERROR: No project specified. Use --project <name> or set SPECIFY_PROJECT" >&2
                return 1
                ;;
            prompt)
                echo "ERROR: No project specified. Use --project <name> or set SPECIFY_PROJECT" >&2
                return 1
                ;;
            current)
                # Try to use current directory name
                basename "$PWD"
                return 0
                ;;
        esac
    fi
    
    return 1
}

# Get the full path to a project's git repository
get_project_root() {
    # Check explicit env var first
    if [[ -n "${SPECIFY_PROJECT_ROOT:-}" ]]; then
        echo "$SPECIFY_PROJECT_ROOT"
        return 0
    fi
    
    # If in a git repo, use it
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
        git rev-parse --show-toplevel
        return 0
    fi
    
    # If SPECIFY_PROJECT is set, resolve it within workspace
    if [[ -n "${SPECIFY_PROJECT:-}" ]]; then
        local workspace_root
        if workspace_root=$(get_workspace_root); then
            local project_path="$workspace_root/$SPECIFY_PROJECT"
            if [[ -d "$project_path" ]]; then
                echo "$project_path"
                return 0
            fi
        fi
    fi
    
    echo "ERROR: Cannot determine project root. Set SPECIFY_PROJECT or cd into a repo." >&2
    return 1
}

# List all discovered projects in the workspace
list_projects() {
    local workspace_root
    if ! workspace_root=$(get_workspace_root); then
        echo "ERROR: Not in a workspace" >&2
        return 1
    fi
    
    # Find all git repositories in workspace
    for dir in "$workspace_root"/*/; do
        [[ -d "$dir" ]] || continue
        local name
        name=$(basename "$dir")
        
        # Skip excluded patterns
        case "$name" in
            node_modules|.git|.specify|.opencode|specs|__pycache__|.venv|venv|scripts|templates|memory|docs|media)
                continue
                ;;
        esac
        
        # Check if it's a git repo
        if [[ -d "$dir/.git" ]] || git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
            echo "$name"
        fi
    done
}

# =============================================================================
# LEGACY FUNCTIONS (Backward compatible)
# =============================================================================

# Get repository root, with fallback for non-git repositories
# In workspace mode, this returns the project root
get_repo_root() {
    # In workspace mode with explicit project, return project root
    if is_workspace_mode && [[ -n "${SPECIFY_PROJECT:-}" ]]; then
        get_project_root
        return
    fi
    
    # Standard git detection
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
        git rev-parse --show-toplevel
    else
        # Fall back to script location for non-git repos
        local script_dir="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        (cd "$script_dir/../.." && pwd)
    fi
}

# Get current branch, with fallback for non-git repositories
get_current_branch() {
    # First check if SPECIFY_FEATURE environment variable is set
    if [[ -n "${SPECIFY_FEATURE:-}" ]]; then
        echo "$SPECIFY_FEATURE"
        return
    fi

    # Then check git if available
    if git rev-parse --abbrev-ref HEAD >/dev/null 2>&1; then
        git rev-parse --abbrev-ref HEAD
        return
    fi

    # For non-git repos, try to find the latest feature directory
    local specs_dir
    specs_dir=$(get_specs_dir)

    if [[ -d "$specs_dir" ]]; then
        local latest_feature=""
        local highest=0

        for dir in "$specs_dir"/*; do
            if [[ -d "$dir" ]]; then
                local dirname=$(basename "$dir")
                # Match both old (001-feature) and new (project-001-feature) formats
                if [[ "$dirname" =~ ^([a-z0-9_-]+-)?([0-9]{3})- ]]; then
                    local number=${BASH_REMATCH[2]}
                    number=$((10#$number))
                    if [[ "$number" -gt "$highest" ]]; then
                        highest=$number
                        latest_feature=$dirname
                    fi
                fi
            fi
        done

        if [[ -n "$latest_feature" ]]; then
            echo "$latest_feature"
            return
        fi
    fi

    echo "main"  # Final fallback
}

# Check if we have git available
has_git() {
    git rev-parse --show-toplevel >/dev/null 2>&1
}

# =============================================================================
# FEATURE BRANCH VALIDATION
# =============================================================================

check_feature_branch() {
    local branch="$1"
    local has_git_repo="$2"

    # For non-git repos, we can't enforce branch naming but still provide output
    if [[ "$has_git_repo" != "true" ]]; then
        echo "[specify] Warning: Git repository not detected; skipped branch validation" >&2
        return 0
    fi

    # In workspace mode, branches may have project prefix: project-001-feature
    # In legacy mode, branches are just: 001-feature
    if is_workspace_mode; then
        if [[ ! "$branch" =~ ^[a-z0-9_-]+-[0-9]{3}- ]] && [[ ! "$branch" =~ ^[0-9]{3}- ]]; then
            echo "ERROR: Not on a feature branch. Current branch: $branch" >&2
            echo "Feature branches should be named like: project-001-feature-name or 001-feature-name" >&2
            return 1
        fi
    else
        if [[ ! "$branch" =~ ^[0-9]{3}- ]]; then
            echo "ERROR: Not on a feature branch. Current branch: $branch" >&2
            echo "Feature branches should be named like: 001-feature-name" >&2
            return 1
        fi
    fi

    return 0
}

# =============================================================================
# FEATURE DIRECTORY RESOLUTION
# =============================================================================

get_feature_dir() { echo "$1/specs/$2"; }

# Extract project name from branch name (for workspace mode)
# e.g., "monorepo-001-feature" -> "monorepo"
extract_project_from_branch() {
    local branch="$1"
    
    # Check if branch has project prefix: project-001-feature
    if [[ "$branch" =~ ^([a-z0-9_-]+)-[0-9]{3}- ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    return 1
}

# Extract feature number from branch name
# e.g., "monorepo-001-feature" -> "001" or "001-feature" -> "001"
extract_number_from_branch() {
    local branch="$1"
    
    # Try project-prefixed format first: project-001-feature
    if [[ "$branch" =~ ^[a-z0-9_-]+-([0-9]{3})- ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    # Try legacy format: 001-feature
    if [[ "$branch" =~ ^([0-9]{3})- ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    return 1
}

# Find feature directory by numeric prefix instead of exact branch match
# This allows multiple branches to work on the same spec (e.g., 004-fix-bug, 004-add-feature)
# Updated for workspace mode with project-prefixed branches
find_feature_dir_by_prefix() {
    local root="$1"
    local branch_name="$2"
    local specs_dir
    
    # Determine specs directory based on mode
    if is_workspace_mode; then
        specs_dir=$(get_specs_dir)
        
        # Extract project from branch if present
        local project
        if project=$(extract_project_from_branch "$branch_name"); then
            # Centralized: specs are in workspace/specs/project/
            specs_dir="$specs_dir/$project"
        fi
    else
        specs_dir="$root/specs"
    fi
    
    # Extract numeric prefix from branch
    local prefix
    if ! prefix=$(extract_number_from_branch "$branch_name"); then
        # If branch doesn't have numeric prefix, fall back to exact match
        echo "$specs_dir/$branch_name"
        return
    fi

    # Search for directories in specs/ that start with this prefix
    local matches=()
    if [[ -d "$specs_dir" ]]; then
        for dir in "$specs_dir"/"$prefix"-* "$specs_dir"/*-"$prefix"-*; do
            if [[ -d "$dir" ]]; then
                matches+=("$(basename "$dir")")
            fi
        done
    fi

    # Handle results
    if [[ ${#matches[@]} -eq 0 ]]; then
        # No match found - return the branch name path (will fail later with clear error)
        echo "$specs_dir/$branch_name"
    elif [[ ${#matches[@]} -eq 1 ]]; then
        # Exactly one match - perfect!
        echo "$specs_dir/${matches[0]}"
    else
        # Multiple matches - this shouldn't happen with proper naming convention
        echo "ERROR: Multiple spec directories found with prefix '$prefix': ${matches[*]}" >&2
        echo "Please ensure only one spec directory exists per numeric prefix." >&2
        echo "$specs_dir/$branch_name"  # Return something to avoid breaking the script
    fi
}

# =============================================================================
# FEATURE PATHS
# =============================================================================

get_feature_paths() {
    local repo_root=$(get_repo_root)
    local current_branch=$(get_current_branch)
    local has_git_repo="false"
    local workspace_root=""
    local project_name=""
    local workspace_mode="false"

    if has_git; then
        has_git_repo="true"
    fi
    
    # Workspace-specific variables
    if is_workspace_mode; then
        workspace_root=$(get_workspace_root)
        project_name=$(get_project_name 2>/dev/null || echo "")
        workspace_mode="true"
    fi

    # Use prefix-based lookup to support multiple branches per spec
    local feature_dir=$(find_feature_dir_by_prefix "$repo_root" "$current_branch")

    cat <<EOF
REPO_ROOT='$repo_root'
CURRENT_BRANCH='$current_branch'
HAS_GIT='$has_git_repo'
WORKSPACE_ROOT='$workspace_root'
PROJECT_NAME='$project_name'
WORKSPACE_MODE='$workspace_mode'
FEATURE_DIR='$feature_dir'
FEATURE_SPEC='$feature_dir/spec.md'
IMPL_PLAN='$feature_dir/plan.md'
TASKS='$feature_dir/tasks.md'
RESEARCH='$feature_dir/research.md'
DATA_MODEL='$feature_dir/data-model.md'
QUICKSTART='$feature_dir/quickstart.md'
CONTRACTS_DIR='$feature_dir/contracts'
EOF
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

check_file() { [[ -f "$1" ]] && echo "  ✓ $2" || echo "  ✗ $2"; }
check_dir() { [[ -d "$1" && -n $(ls -A "$1" 2>/dev/null) ]] && echo "  ✓ $2" || echo "  ✗ $2"; }

# =============================================================================
# FEATURE SHORTHAND PARSING
# =============================================================================

# Parse feature shorthand like "monorepo-001" or "monorepo-001-user-auth"
# Returns: PROJECT_NAME, FEATURE_NUM, FEATURE_DIR
# Usage: eval $(parse_feature_shorthand "monorepo-001")
parse_feature_shorthand() {
    local shorthand="$1"
    local workspace_root
    
    if ! workspace_root=$(get_workspace_root 2>/dev/null); then
        echo "echo 'ERROR: Not in a workspace' >&2; return 1"
        return 1
    fi
    
    local specs_dir
    specs_dir=$(get_specs_dir)
    local project=""
    local feature_num=""
    local feature_dir=""
    
    # Pattern 1: project-NNN (e.g., "monorepo-001")
    if [[ "$shorthand" =~ ^([a-z0-9_-]+)-([0-9]{3})$ ]]; then
        project="${BASH_REMATCH[1]}"
        feature_num="${BASH_REMATCH[2]}"
    # Pattern 2: project-NNN-name (e.g., "monorepo-001-user-auth")
    elif [[ "$shorthand" =~ ^([a-z0-9_-]+)-([0-9]{3})-.+ ]]; then
        project="${BASH_REMATCH[1]}"
        feature_num="${BASH_REMATCH[2]}"
    else
        echo "echo 'ERROR: Invalid shorthand format. Use: project-NNN (e.g., monorepo-001)' >&2; return 1"
        return 1
    fi
    
    # Find the feature directory
    local project_specs="$specs_dir/$project"
    if [[ ! -d "$project_specs" ]]; then
        echo "echo 'ERROR: No specs found for project: $project' >&2; return 1"
        return 1
    fi
    
    # Look for directory matching the feature number
    for dir in "$project_specs"/"$feature_num"-*; do
        if [[ -d "$dir" ]]; then
            feature_dir="$dir"
            break
        fi
    done
    
    if [[ -z "$feature_dir" || ! -d "$feature_dir" ]]; then
        echo "echo 'ERROR: No feature found matching $project-$feature_num in $project_specs' >&2; return 1"
        return 1
    fi
    
    # Output variables for eval
    cat <<EOF
SHORTHAND_PROJECT='$project'
SHORTHAND_FEATURE_NUM='$feature_num'
SHORTHAND_FEATURE_DIR='$feature_dir'
SHORTHAND_FEATURE_NAME='$(basename "$feature_dir")'
EOF
}

# List all active features in workspace (for help/listing)
list_workspace_features() {
    local workspace_root
    
    if ! workspace_root=$(get_workspace_root 2>/dev/null); then
        echo "ERROR: Not in a workspace" >&2
        return 1
    fi
    
    local specs_dir
    specs_dir=$(get_specs_dir)
    
    if [[ ! -d "$specs_dir" ]]; then
        echo "No features found."
        return 0
    fi
    
    echo "Available features:"
    echo ""
    
    for project_dir in "$specs_dir"/*/; do
        [[ -d "$project_dir" ]] || continue
        local project=$(basename "$project_dir")
        
        for feature_dir in "$project_dir"/*; do
            [[ -d "$feature_dir" ]] || continue
            local feature=$(basename "$feature_dir")
            
            # Extract number from feature name
            if [[ "$feature" =~ ^([0-9]{3})- ]]; then
                local num="${BASH_REMATCH[1]}"
                local has_spec="[ ]"
                local has_plan="[ ]"
                local has_tasks="[ ]"
                
                [[ -f "$feature_dir/spec.md" ]] && has_spec="[x]"
                [[ -f "$feature_dir/plan.md" ]] && has_plan="[x]"
                [[ -f "$feature_dir/tasks.md" ]] && has_tasks="[x]"
                
                printf "  %-20s %s  spec:%s plan:%s tasks:%s\n" "$project-$num" "$feature" "$has_spec" "$has_plan" "$has_tasks"
            fi
        done
    done
}

# =============================================================================
# FEATURE NUMBER GENERATION
# =============================================================================

# Get next feature number across entire workspace (for centralized specs)
get_next_workspace_feature_number() {
    local project="$1"
    local highest=0
    local specs_dir
    
    specs_dir=$(get_specs_dir)
    
    if is_workspace_mode; then
        local workspace_root
        workspace_root=$(get_workspace_root)
        
        # Check centralized specs for this project
        local project_specs="$specs_dir/$project"
        if [[ -d "$project_specs" ]]; then
            for dir in "$project_specs"/*; do
                [[ -d "$dir" ]] || continue
                local dirname
                dirname=$(basename "$dir")
                if [[ "$dirname" =~ ^([0-9]{3})- ]]; then
                    local num=$((10#${BASH_REMATCH[1]}))
                    [[ "$num" -gt "$highest" ]] && highest=$num
                fi
            done
        fi
        
        # Check all branches in the project repo for this project's prefix
        local project_root="$workspace_root/$project"
        if [[ -d "$project_root/.git" ]] || git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
            git -C "$project_root" fetch --all --prune 2>/dev/null || true
            
            for branch in $(git -C "$project_root" branch -a 2>/dev/null | sed 's/^[* ]*//; s|^remotes/[^/]*/||' | sort -u); do
                # Match project-001-feature pattern
                if [[ "$branch" =~ ^${project}-([0-9]{3})- ]]; then
                    local num=$((10#${BASH_REMATCH[1]}))
                    [[ "$num" -gt "$highest" ]] && highest=$num
                fi
                # Also match legacy 001-feature pattern
                if [[ "$branch" =~ ^([0-9]{3})- ]]; then
                    local num=$((10#${BASH_REMATCH[1]}))
                    [[ "$num" -gt "$highest" ]] && highest=$num
                fi
            done
        fi
    fi
    
    echo $((highest + 1))
}
