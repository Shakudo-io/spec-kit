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

# Parse a YAML list from workspace.yaml
# Usage: get_workspace_config_list "key"
# Returns one item per line, empty if key not found or list is empty
get_workspace_config_list() {
    local key="$1"
    
    local config_file
    if ! config_file=$(get_workspace_config_file); then
        return
    fi
    
    # Extract list items following "key:" or "key: []"
    # Handles both inline empty [] and multi-line list with "  - item" format
    awk -v key="$key" '
        BEGIN { in_list = 0 }
        # Match the key line
        $0 ~ "^" key ":" {
            in_list = 1
            # Check for inline empty array
            if ($0 ~ /\[\]/) {
                in_list = 0
                next
            }
            next
        }
        # If in list, capture items starting with "  - "
        in_list && /^[[:space:]]+-[[:space:]]/ {
            sub(/^[[:space:]]+-[[:space:]]*/, "")
            sub(/[[:space:]]*$/, "")
            # Remove quotes if present
            gsub(/^["'"'"']|["'"'"']$/, "")
            print
            next
        }
        # Exit list on non-indented line or different key
        in_list && /^[^[:space:]]/ { in_list = 0 }
    ' "$config_file"
}

# Check if a project is archived
# Usage: is_project_archived "project-name"
is_project_archived() {
    local project="$1"
    local archived
    archived=$(get_workspace_config_list "archived_projects")
    
    if [[ -z "$archived" ]]; then
        return 1
    fi
    
    echo "$archived" | grep -qx "$project"
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

# List all discovered projects in the workspace (excludes archived projects)
# Usage: list_projects [--include-archived]
list_projects() {
    local include_archived=false
    if [[ "${1:-}" == "--include-archived" ]]; then
        include_archived=true
    fi
    
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
        
        if ! $include_archived && is_project_archived "$name"; then
            continue
        fi
        
        if [[ -d "$dir/.git" ]] || [[ -d "$dir/.specify" ]] || git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
            echo "$name"
        fi
    done
}

# List projects with detailed git information (repo URL, branch, worktree info)
# Usage: list_projects_detailed [--include-archived]
list_projects_detailed() {
    local include_archived=false
    if [[ "${1:-}" == "--include-archived" ]]; then
        include_archived=true
    fi
    
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
        
        if ! $include_archived && is_project_archived "$name"; then
            continue
        fi
        
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
    
    local strategy
    strategy=$(get_workspace_config "spec_strategy" "distributed")
    
    declare -A seen_repos
    declare -A seen_specs
    
    # First scan centralized specs directory if strategy is centralized
    if [[ "$strategy" == "centralized" ]]; then
        local centralized_specs_dir
        centralized_specs_dir=$(get_workspace_config "specs_dir" "$workspace_root/specs")
        
        if [[ -d "$centralized_specs_dir" ]]; then
            for project_dir in "$centralized_specs_dir"/*/; do
                [[ -d "$project_dir" ]] || continue
                local project_name
                project_name=$(basename "$project_dir")
                
                local repo_url=""
                local branch=""
                local is_worktree="false"
                local project_root="$workspace_root/$project_name"
                
                if [[ -d "$project_root" ]] && git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
                    repo_url=$(git -C "$project_root" remote get-url origin 2>/dev/null || echo "")
                    branch=$(git -C "$project_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
                fi
                
                for feature_dir in "$project_dir"/*/; do
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
                    
                    seen_specs["${project_name}:${feature_name}"]="1"
                    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                        "$project_name" "$feature_name" "$spec_path" "$has_spec" "$has_plan" "$has_tasks" "$last_modified" "$repo_url" "$branch" "$is_worktree"
                done
            done
        fi
    fi
    
    # Then scan individual project directories (for distributed mode or hybrid)
    for dir in "$workspace_root"/*/; do
        [[ -d "$dir" ]] || continue
        local project_name
        project_name=$(basename "$dir")
        
        case "$project_name" in
            node_modules|.git|.specify|.opencode|__pycache__|.venv|venv|.*|.claude|.cursor|.github|specs)
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
            local spec_key="${project_name}:${feature_name}"
            if [[ -n "${seen_specs[$spec_key]:-}" ]]; then
                continue
            fi
            seen_specs[$spec_key]="1"
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
        
        local rel_spec_path="${spec_path#$workspace_root/}"
        rel_spec_path="${rel_spec_path//\/\//\/}"
        local spec_dir
        spec_dir=$(dirname "$rel_spec_path")
        local rel_plan_path="${spec_dir}/plan.md"
        local rel_tasks_path="${spec_dir}/tasks.md"
        
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
# CONSTITUTION PATH RESOLUTION
# =============================================================================

# Get the path to the constitution file based on workspace.yaml configuration
# Respects the constitution_location setting: "workspace" or "project"
# Usage: constitution_path=$(get_constitution_path [project_name])
# Returns: Absolute path to constitution.md
get_constitution_path() {
    local project_name="${1:-}"
    
    if is_workspace_mode; then
        local workspace_root
        workspace_root=$(get_workspace_root)
        
        # Read constitution_location from workspace.yaml (default: workspace)
        local constitution_location
        constitution_location=$(get_workspace_config "constitution_location" "workspace")
        
        case "$constitution_location" in
            workspace)
                # Use shared constitution at workspace level
                echo "$workspace_root/.specify/memory/constitution.md"
                ;;
            project)
                # Use per-project constitution
                if [[ -z "$project_name" ]]; then
                    # Try to detect project from current directory
                    project_name=$(get_project_name 2>/dev/null || echo "")
                fi
                
                if [[ -n "$project_name" ]]; then
                    local project_constitution="$workspace_root/$project_name/.specify/memory/constitution.md"
                    if [[ -f "$project_constitution" ]]; then
                        echo "$project_constitution"
                    else
                        # Fallback to workspace constitution if project doesn't have one
                        echo "$workspace_root/.specify/memory/constitution.md"
                    fi
                else
                    # No project context, use workspace constitution
                    echo "$workspace_root/.specify/memory/constitution.md"
                fi
                ;;
            *)
                # Unknown value, default to workspace
                echo "$workspace_root/.specify/memory/constitution.md"
                ;;
        esac
    else
        # Legacy single-repo mode: constitution in repo's .specify/memory/
        local repo_root
        repo_root=$(get_repo_root)
        echo "$repo_root/.specify/memory/constitution.md"
    fi
}

# =============================================================================
# FEATURE SHORTHAND PARSING
# =============================================================================

# Parse feature shorthand/reference
# Supports:
#   - Legacy format: "project-NNN" or "project-NNN-name" (e.g., "monorepo-001")
#   - Workspace format: "project:feature" (e.g., "monorepo:001-user-auth")
# Returns: SHORTHAND_PROJECT, SHORTHAND_FEATURE_NUM, SHORTHAND_FEATURE_DIR, SHORTHAND_FEATURE_NAME
# Usage: eval $(parse_feature_shorthand "monorepo-001")
#        eval $(parse_feature_shorthand "monorepo:001-user-auth")
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
    local feature_name=""
    
    # Pattern 0: project:feature (workspace rollup format, e.g., "monorepo:001-user-auth")
    if [[ "$shorthand" == *":"* ]]; then
        project="${shorthand%%:*}"
        feature_name="${shorthand#*:}"
        
        # Try to resolve via specs-index.json first (uses resolve_spec_path)
        if feature_dir=$(resolve_spec_path "$shorthand" 2>/dev/null); then
            # Extract feature_num from feature_name if it starts with NNN
            if [[ "$feature_name" =~ ^([0-9]{3}) ]]; then
                feature_num="${BASH_REMATCH[1]}"
            else
                feature_num="000"  # Default if no number prefix
            fi
        else
            # Fallback: try to find in centralized specs dir first, then project's own specs dir
            local found="false"
            
            # Check centralized specs directory (workspace/specs/project/feature)
            if [[ -d "$specs_dir/$project/$feature_name" ]]; then
                feature_dir="$specs_dir/$project/$feature_name"
                found="true"
            fi
            
            # Check project's internal specs directories
            if [[ "$found" == "false" ]]; then
                local project_specs="$workspace_root/$project/.specify/specs"
                if [[ -d "$project_specs/$feature_name" ]]; then
                    feature_dir="$project_specs/$feature_name"
                    found="true"
                fi
            fi
            
            if [[ "$found" == "false" ]]; then
                local project_specs="$workspace_root/$project/specs"
                if [[ -d "$project_specs/$feature_name" ]]; then
                    feature_dir="$project_specs/$feature_name"
                    found="true"
                fi
            fi
            
            if [[ "$found" == "false" ]]; then
                echo "echo 'ERROR: Feature \"$feature_name\" not found in project \"$project\"' >&2; return 1"
                return 1
            fi
            
            if [[ "$feature_name" =~ ^([0-9]{3}) ]]; then
                feature_num="${BASH_REMATCH[1]}"
            else
                feature_num="000"
            fi
        fi
    # Pattern 1: project-NNN (e.g., "monorepo-001")
    elif [[ "$shorthand" =~ ^([a-z0-9_-]+)-([0-9]{3})$ ]]; then
        project="${BASH_REMATCH[1]}"
        feature_num="${BASH_REMATCH[2]}"
    # Pattern 2: project-NNN-name (e.g., "monorepo-001-user-auth")
    elif [[ "$shorthand" =~ ^([a-z0-9_-]+)-([0-9]{3})-.+ ]]; then
        project="${BASH_REMATCH[1]}"
        feature_num="${BASH_REMATCH[2]}"
    else
        echo "echo 'ERROR: Invalid shorthand format. Use: project-NNN (e.g., monorepo-001) or project:feature (e.g., monorepo:001-user-auth)' >&2; return 1"
        return 1
    fi
    
    # If we don't have feature_dir yet (legacy format), find it
    if [[ -z "$feature_dir" ]]; then
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
    fi
    
    # Get feature_name if not already set
    if [[ -z "$feature_name" ]]; then
        feature_name="$(basename "$feature_dir")"
    fi
    
    # Output variables for eval
    cat <<EOF
SHORTHAND_PROJECT='$project'
SHORTHAND_FEATURE_NUM='$feature_num'
SHORTHAND_FEATURE_DIR='$feature_dir'
SHORTHAND_FEATURE_NAME='$feature_name'
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
# SOURCE DIRECTORY RESOLUTION (for workspace mode)
# =============================================================================

# Resolve the source directory for a feature in workspace mode
# This is where actual source code changes should be made (worktree or main checkout)
# Returns: Absolute path to source directory, IS_WORKTREE flag, and MAIN_PROJECT if worktree
#
# Logic:
# 1. If a worktree exists for this feature's branch → use worktree
# 2. Else if main checkout is on the feature branch → use main checkout
# 3. Else → use main checkout (warn that branch may need switching)
resolve_source_dir() {
    local project="$1"
    local feature="$2"  # e.g., "006-speed-dashboard-image"
    local workspace_root
    
    if ! workspace_root=$(get_workspace_root 2>/dev/null); then
        echo "ERROR: Not in a workspace" >&2
        return 1
    fi
    
    local branch_prefix
    branch_prefix=$(get_workspace_config "branch_naming.include_project_prefix" "true")
    
    local expected_branch
    if [[ "$branch_prefix" == "true" ]]; then
        expected_branch="${project}-${feature}"
    else
        expected_branch="${feature}"
    fi
    
    local main_checkout="$workspace_root/$project"
    local worktree_base
    worktree_base=$(get_workspace_config "worktrees.base_dir" "$workspace_root")
    
    # Check for worktree with various naming patterns
    local worktree_path=""
    local is_worktree="false"
    local checked_paths=()
    
    # Pattern 1: project-feature (e.g., monorepo-006-speed-dashboard-image)
    local wt_pattern1="$worktree_base/${project}-${feature}"
    checked_paths+=("$wt_pattern1")
    if [[ -d "$wt_pattern1" ]] && git -C "$wt_pattern1" rev-parse --git-dir >/dev/null 2>&1; then
        worktree_path="$wt_pattern1"
        is_worktree="true"
    fi
    
    # Pattern 2: Just feature name (e.g., 006-speed-dashboard-image) - for legacy setups
    if [[ -z "$worktree_path" ]]; then
        local wt_pattern2="$worktree_base/${feature}"
        checked_paths+=("$wt_pattern2")
        if [[ -d "$wt_pattern2" ]] && git -C "$wt_pattern2" rev-parse --git-dir >/dev/null 2>&1; then
            worktree_path="$wt_pattern2"
            is_worktree="true"
        fi
    fi
    
    # Pattern 3: Check if there's any worktree on the expected branch (only if not already found)
    if [[ -z "$worktree_path" ]] && { [[ -d "$main_checkout/.git" ]] || git -C "$main_checkout" rev-parse --git-dir >/dev/null 2>&1; }; then
        while IFS= read -r line; do
            if [[ "$line" == "worktree "* ]]; then
                local wt_dir="${line#worktree }"
                [[ "$wt_dir" == "$main_checkout" ]] && continue
                local wt_branch
                wt_branch=$(git -C "$wt_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
                if [[ "$wt_branch" == "$expected_branch" ]] || [[ "$wt_branch" == "$feature" ]]; then
                    worktree_path="$wt_dir"
                    is_worktree="true"
                    break
                fi
            fi
        done < <(git -C "$main_checkout" worktree list --porcelain 2>/dev/null || true)
    fi
    
    # Determine source directory
    local source_dir=""
    local source_branch=""
    local branch_status="ok"
    
    if [[ -n "$worktree_path" ]]; then
        source_dir="$worktree_path"
        source_branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    elif [[ -d "$main_checkout" ]]; then
        source_dir="$main_checkout"
        source_branch=$(git -C "$main_checkout" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        
        # Check if main checkout is on the expected branch
        if [[ "$source_branch" != "$expected_branch" ]] && [[ "$source_branch" != "$feature" ]]; then
            branch_status="switch_needed"
        fi
    else
        echo "ERROR: Cannot find source directory for project '$project'" >&2
        return 1
    fi
    
    # Output in eval-able format
    cat <<EOF
SOURCE_DIR='$source_dir'
SOURCE_BRANCH='$source_branch'
IS_WORKTREE='$is_worktree'
EXPECTED_BRANCH='$expected_branch'
BRANCH_STATUS='$branch_status'
EOF
}

# Get source directory info as JSON (for check-prerequisites.sh --json)
resolve_source_dir_json() {
    local project="$1"
    local feature="$2"
    
    local result
    if ! result=$(resolve_source_dir "$project" "$feature" 2>/dev/null); then
        printf '{"source_dir":"","is_worktree":false,"branch_status":"error","error":"Could not resolve source directory"}'
        return 1
    fi
    
    eval "$result"
    
    printf '{"source_dir":"%s","source_branch":"%s","is_worktree":%s,"expected_branch":"%s","branch_status":"%s"}' \
        "$SOURCE_DIR" "$SOURCE_BRANCH" "$IS_WORKTREE" "$EXPECTED_BRANCH" "$BRANCH_STATUS"
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
