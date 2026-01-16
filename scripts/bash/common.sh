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
    
    for dir in "$workspace_root"/*/; do
        [[ -d "$dir" ]] || continue
        local name
        name=$(basename "$dir")
        
        # Skip excluded patterns and hidden directories
        case "$name" in
            node_modules|.git|.specify|.opencode|specs|__pycache__|.venv|venv|scripts|templates|memory|docs|media|.*|.claude|.cursor|.github)
                continue
                ;;
        esac
        
        # Check if it's a git repo OR has .specify directory (spec-kit initialized)
        if [[ -d "$dir/.git" ]] || [[ -d "$dir/.specify" ]] || git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
            echo "$name"
        fi
    done
}

# List projects with detailed git information (repo URL, branch, worktree info)
list_projects_detailed() {
    local workspace_root
    if ! workspace_root=$(get_workspace_root); then
        echo "ERROR: Not in a workspace" >&2
        return 1
    fi
    
    for dir in "$workspace_root"/*/; do
        [[ -d "$dir" ]] || continue
        local name
        name=$(basename "$dir")
        
        case "$name" in
            node_modules|.git|.specify|.opencode|specs|__pycache__|.venv|venv|scripts|templates|memory|docs|media|.*|.claude|.cursor|.github)
                continue
                ;;
        esac
        
        if [[ -d "$dir/.git" ]] || [[ -d "$dir/.specify" ]] || git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
            local remote_url=""
            local branch=""
            local has_git="false"
            local is_worktree="false"
            local main_worktree=""
            
            if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
                has_git="true"
                remote_url=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "")
                branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
                
                local git_dir
                git_dir=$(git -C "$dir" rev-parse --git-dir 2>/dev/null)
                if [[ "$git_dir" == *".git/worktrees/"* ]]; then
                    is_worktree="true"
                    # Get common git dir and resolve to absolute path (--path-format not available in older git)
                    local common_dir
                    common_dir=$(cd "$dir" && git rev-parse --git-common-dir 2>/dev/null)
                    # Resolve to absolute path and strip /.git suffix
                    main_worktree=$(cd "$dir" && cd "$common_dir" && pwd | sed 's|/.git$||')
                    main_worktree=$(basename "$main_worktree")
                fi
            fi
            
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$has_git" "$remote_url" "$branch" "$is_worktree" "$main_worktree"
        fi
    done
}

# =============================================================================
# SPEC ROLLUP FUNCTIONS
# =============================================================================

# Scan a single project for specs, returns tab-separated: feature_name, spec_path, has_spec, has_plan, has_tasks, last_modified
scan_project_for_specs() {
    local project_dir="$1"
    [[ -d "$project_dir" ]] || return 1
    
    local specs_dir=""
    if [[ -d "$project_dir/.specify/specs" ]]; then
        specs_dir="$project_dir/.specify/specs"
    elif [[ -d "$project_dir/specs" ]]; then
        specs_dir="$project_dir/specs"
    else
        return 0
    fi
    
    for feature_dir in "$specs_dir"/*/; do
        [[ -d "$feature_dir" ]] || continue
        local feature_name
        feature_name=$(basename "$feature_dir")
        
        [[ "$feature_name" == "*" ]] && continue
        
        local has_spec="false"
        local has_plan="false"
        local has_tasks="false"
        local last_modified="0"
        local spec_path="${feature_dir}spec.md"
        
        if [[ -f "${feature_dir}spec.md" ]]; then
            has_spec="true"
            local mod_time
            mod_time=$(stat -c %Y "${feature_dir}spec.md" 2>/dev/null || stat -f %m "${feature_dir}spec.md" 2>/dev/null || echo "0")
            [[ "$mod_time" -gt "$last_modified" ]] && last_modified="$mod_time"
        fi
        
        if [[ -f "${feature_dir}plan.md" ]]; then
            has_plan="true"
            local mod_time
            mod_time=$(stat -c %Y "${feature_dir}plan.md" 2>/dev/null || stat -f %m "${feature_dir}plan.md" 2>/dev/null || echo "0")
            [[ "$mod_time" -gt "$last_modified" ]] && last_modified="$mod_time"
        fi
        
        if [[ -f "${feature_dir}tasks.md" ]]; then
            has_tasks="true"
            local mod_time
            mod_time=$(stat -c %Y "${feature_dir}tasks.md" 2>/dev/null || stat -f %m "${feature_dir}tasks.md" 2>/dev/null || echo "0")
            [[ "$mod_time" -gt "$last_modified" ]] && last_modified="$mod_time"
        fi
        
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$feature_name" "$spec_path" "$has_spec" "$has_plan" "$has_tasks" "$last_modified"
    done
}

# Scan entire workspace for specs with worktree deduplication
# Output: project_name, feature_name, spec_path, has_spec, has_plan, has_tasks, last_modified, repo_url, branch, is_worktree
scan_workspace_specs() {
    local workspace_root
    local include_worktrees="${1:-false}"
    
    if ! workspace_root=$(get_workspace_root); then
        echo "ERROR: Not in a workspace" >&2
        return 1
    fi
    
    declare -A seen_repos
    
    for dir in "$workspace_root"/*/; do
        [[ -d "$dir" ]] || continue
        local project_name
        project_name=$(basename "$dir")
        
        case "$project_name" in
            node_modules|.git|.specify|.opencode|__pycache__|.venv|venv|.*|.claude|.cursor|.github)
                continue
                ;;
        esac
        
        local repo_url=""
        local branch=""
        local is_worktree="false"
        local main_worktree=""
        
        if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
            repo_url=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "")
            branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
            
            local git_dir
            git_dir=$(git -C "$dir" rev-parse --git-dir 2>/dev/null)
            if [[ "$git_dir" == *".git/worktrees/"* ]]; then
                is_worktree="true"
                local common_dir
                common_dir=$(cd "$dir" && git rev-parse --git-common-dir 2>/dev/null)
                main_worktree=$(cd "$dir" && cd "$common_dir" && pwd | sed 's|/.git$||')
                main_worktree=$(basename "$main_worktree")
            fi
            
            if [[ "$include_worktrees" != "true" ]] && [[ -n "$repo_url" ]]; then
                if [[ "$is_worktree" == "true" ]]; then
                    continue
                fi
                if [[ -n "${seen_repos[$repo_url]:-}" ]]; then
                    continue
                fi
                seen_repos[$repo_url]="$project_name"
            fi
        fi
        
        while IFS=$'\t' read -r feature_name spec_path has_spec has_plan has_tasks last_modified; do
            [[ -z "$feature_name" ]] && continue
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$project_name" "$feature_name" "$spec_path" "$has_spec" "$has_plan" "$has_tasks" "$last_modified" "$repo_url" "$branch" "$is_worktree"
        done < <(scan_project_for_specs "$dir")
    done
}

# Generate specs index files (JSON and Markdown) at workspace level
generate_specs_index() {
    local workspace_root
    local include_worktrees="${1:-false}"
    
    if ! workspace_root=$(get_workspace_root); then
        echo "ERROR: Not in a workspace" >&2
        return 1
    fi
    
    local index_json="$workspace_root/.specify/specs-index.json"
    local index_md="$workspace_root/.specify/specs-index.md"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    mkdir -p "$workspace_root/.specify"
    
    local json_specs=""
    local md_content="# Workspace Specs Index\n\n"
    md_content+="**Generated:** $timestamp\n"
    md_content+="**Workspace:** $workspace_root\n\n"
    md_content+="| Project | Feature | Spec | Plan | Tasks | Branch |\n"
    md_content+="|---------|---------|------|------|-------|--------|\n"
    
    local spec_count=0
    local first=true
    
    while IFS=$'\t' read -r project feature spec_path has_spec has_plan has_tasks last_modified repo_url branch is_worktree; do
        [[ -z "$project" ]] && continue
        
        local id="${project}:${feature}"
        local rel_spec_path="${project}/.specify/specs/${feature}/spec.md"
        local rel_plan_path="${project}/.specify/specs/${feature}/plan.md"
        local rel_tasks_path="${project}/.specify/specs/${feature}/tasks.md"
        
        if [[ ! -f "$workspace_root/$rel_spec_path" ]]; then
            rel_spec_path="${project}/specs/${feature}/spec.md"
            rel_plan_path="${project}/specs/${feature}/plan.md"
            rel_tasks_path="${project}/specs/${feature}/tasks.md"
        fi
        
        if $first; then
            first=false
        else
            json_specs+=","
        fi
        
        json_specs+="\n    {"
        json_specs+="\"id\":\"$id\","
        json_specs+="\"project\":\"$project\","
        json_specs+="\"feature\":\"$feature\","
        json_specs+="\"spec_path\":\"$rel_spec_path\","
        json_specs+="\"plan_path\":\"$rel_plan_path\","
        json_specs+="\"tasks_path\":\"$rel_tasks_path\","
        json_specs+="\"has_spec\":$has_spec,"
        json_specs+="\"has_plan\":$has_plan,"
        json_specs+="\"has_tasks\":$has_tasks,"
        json_specs+="\"repo_url\":\"$repo_url\","
        json_specs+="\"branch\":\"$branch\","
        json_specs+="\"is_worktree\":$is_worktree,"
        json_specs+="\"last_modified\":$last_modified"
        json_specs+="}"
        
        local spec_icon="$( [[ "$has_spec" == "true" ]] && echo "✓" || echo "-" )"
        local plan_icon="$( [[ "$has_plan" == "true" ]] && echo "✓" || echo "-" )"
        local tasks_icon="$( [[ "$has_tasks" == "true" ]] && echo "✓" || echo "-" )"
        md_content+="| $project | $feature | $spec_icon | $plan_icon | $tasks_icon | $branch |\n"
        
        ((spec_count++))
    done < <(scan_workspace_specs "$include_worktrees")
    
    printf '{\n  "version": "1.0",\n  "workspace_root": "%s",\n  "generated_at": "%s",\n  "spec_count": %d,\n  "specs": [%b\n  ]\n}\n' \
        "$workspace_root" "$timestamp" "$spec_count" "$json_specs" > "$index_json"
    
    md_content+="\n**Total specs:** $spec_count\n"
    printf '%b' "$md_content" > "$index_md"
    
    echo "$spec_count"
}

# Read specs index and return JSON content
read_specs_index() {
    local workspace_root
    if ! workspace_root=$(get_workspace_root); then
        echo "ERROR: Not in a workspace" >&2
        return 1
    fi
    
    local index_json="$workspace_root/.specify/specs-index.json"
    if [[ ! -f "$index_json" ]]; then
        echo "ERROR: Specs index not found. Run rollup first." >&2
        return 1
    fi
    
    cat "$index_json"
}

# Resolve project:feature to absolute spec directory path, auto-refresh if needed
resolve_spec_path() {
    local spec_id="$1"
    local workspace_root
    
    if ! workspace_root=$(get_workspace_root); then
        echo "ERROR: Not in a workspace" >&2
        return 1
    fi
    
    local project="${spec_id%%:*}"
    local feature="${spec_id#*:}"
    
    if [[ "$project" == "$feature" ]] || [[ -z "$feature" ]]; then
        echo "ERROR: Invalid spec ID format. Use project:feature" >&2
        return 1
    fi
    
    local index_json="$workspace_root/.specify/specs-index.json"
    
    if [[ ! -f "$index_json" ]]; then
        echo "INFO: Index missing, generating..." >&2
        generate_specs_index >/dev/null
    fi
    
    local spec_path=""
    if command -v jq >/dev/null 2>&1; then
        spec_path=$(jq -r ".specs[] | select(.id == \"$spec_id\") | .spec_path" "$index_json" 2>/dev/null)
    else
        spec_path=$(grep -o "\"spec_path\":\"[^\"]*\"" "$index_json" | grep "$project.*$feature" | head -1 | sed 's/.*":"\([^"]*\)".*/\1/')
    fi
    
    if [[ -z "$spec_path" ]] || [[ "$spec_path" == "null" ]]; then
        echo "INFO: Spec not in index, refreshing..." >&2
        generate_specs_index >/dev/null
        if command -v jq >/dev/null 2>&1; then
            spec_path=$(jq -r ".specs[] | select(.id == \"$spec_id\") | .spec_path" "$index_json" 2>/dev/null)
        fi
    fi
    
    if [[ -z "$spec_path" ]] || [[ "$spec_path" == "null" ]]; then
        echo "ERROR: Spec '$spec_id' not found" >&2
        return 1
    fi
    
    local full_path="$workspace_root/$spec_path"
    local spec_dir
    spec_dir=$(dirname "$full_path")
    
    if [[ ! -d "$spec_dir" ]]; then
        echo "ERROR: Spec directory not found: $spec_dir" >&2
        return 1
    fi
    
    echo "$spec_dir"
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
