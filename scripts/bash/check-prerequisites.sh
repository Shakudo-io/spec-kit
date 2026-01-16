#!/usr/bin/env bash

# Consolidated prerequisite checking script
#
# This script provides unified prerequisite checking for Spec-Driven Development workflow.
# It replaces the functionality previously spread across multiple scripts.
#
# Usage: ./check-prerequisites.sh [OPTIONS] [feature-shorthand]
#
# ARGUMENTS:
#   feature-shorthand   Feature reference in workspace mode (e.g., "monorepo-001")
#
# OPTIONS:
#   --json              Output in JSON format
#   --require-tasks     Require tasks.md to exist (for implementation phase)
#   --include-tasks     Include tasks.md in AVAILABLE_DOCS list
#   --paths-only        Only output path variables (no validation)
#   --feature <ref>     Explicit feature shorthand (alternative to positional arg)
#   --list-features     List all available features in workspace mode
#   --list-projects     List available projects in workspace mode
#   --workspace-info    Output workspace context (projects, features, mode) as JSON
#   --help, -h          Show help message
#
# OUTPUTS:
#   JSON mode: {"FEATURE_DIR":"...", "AVAILABLE_DOCS":["..."]}
#   Text mode: FEATURE_DIR:... \n AVAILABLE_DOCS: \n ✓/✗ file.md
#   Paths only: REPO_ROOT: ... \n BRANCH: ... \n FEATURE_DIR: ... etc.

set -e

# Parse command line arguments
JSON_MODE=false
REQUIRE_TASKS=false
INCLUDE_TASKS=false
PATHS_ONLY=false
LIST_PROJECTS=false
LIST_PROJECTS_DETAILED=false
LIST_FEATURES=false
LIST_SPECS=false
ROLLUP=false
WORKSPACE_INFO=false
INCLUDE_WORKTREES=false
FORCE_REFRESH=false
FEATURE_SHORTHAND=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            JSON_MODE=true
            shift
            ;;
        --require-tasks)
            REQUIRE_TASKS=true
            shift
            ;;
        --include-tasks)
            INCLUDE_TASKS=true
            shift
            ;;
        --paths-only)
            PATHS_ONLY=true
            shift
            ;;
        --list-projects)
            LIST_PROJECTS=true
            shift
            ;;
        --list-projects-detailed)
            LIST_PROJECTS_DETAILED=true
            shift
            ;;
        --list-features)
            LIST_FEATURES=true
            shift
            ;;
        --list-specs)
            LIST_SPECS=true
            shift
            ;;
        --rollup)
            ROLLUP=true
            shift
            ;;
        --include-worktrees)
            INCLUDE_WORKTREES=true
            shift
            ;;
        --force-refresh)
            FORCE_REFRESH=true
            shift
            ;;
        --workspace-info)
            WORKSPACE_INFO=true
            shift
            ;;
        --feature)
            if [[ -z "$2" || "$2" == --* ]]; then
                echo "ERROR: --feature requires a value (e.g., --feature monorepo-001)" >&2
                exit 1
            fi
            FEATURE_SHORTHAND="$2"
            shift 2
            ;;
        --help|-h)
            cat << 'EOF'
Usage: check-prerequisites.sh [OPTIONS] [feature-shorthand]

Consolidated prerequisite checking for Spec-Driven Development workflow.

ARGUMENTS:
  feature-shorthand   Feature reference in workspace mode (e.g., "monorepo-001")
                      Sets SPECIFY_FEATURE for subsequent operations

OPTIONS:
  --json              Output in JSON format
  --require-tasks     Require tasks.md to exist (for implementation phase)
  --include-tasks     Include tasks.md in AVAILABLE_DOCS list
  --paths-only        Only output path variables (no prerequisite validation)
  --feature <ref>     Explicit feature shorthand (alternative to positional arg)
  --list-features     List all available features in workspace mode
  --list-projects     List available projects in workspace mode
  --list-projects-detailed  List projects with repo URL and branch info
  --list-specs        List all specs across workspace (from index)
  --rollup            Scan workspace and generate specs-index.json
  --include-worktrees Include specs from worktrees (no deduplication)
  --force-refresh     Force index refresh before listing specs
  --workspace-info    Output workspace context (projects, features, mode) as JSON
  --help, -h          Show this help message

WORKSPACE MODE:
  In multi-repo workspaces, use feature shorthand to target specific features:
  
  ./check-prerequisites.sh --json monorepo-001
  ./check-prerequisites.sh --json --feature backend-api-002
  
  The shorthand format is: project-NNN (e.g., monorepo-001, backend-api-002)

EXAMPLES:
  # Check task prerequisites (plan.md required)
  ./check-prerequisites.sh --json
  
  # Check prerequisites for specific feature in workspace
  ./check-prerequisites.sh --json monorepo-001
  
  # Check implementation prerequisites (plan.md + tasks.md required)
  ./check-prerequisites.sh --json --require-tasks --include-tasks
  
  # Get feature paths only (no validation)
  ./check-prerequisites.sh --paths-only
  
  # List available projects in workspace
  ./check-prerequisites.sh --list-projects
  
  # List available features in workspace
  ./check-prerequisites.sh --list-features
  
  # Get full workspace context for AI agents
  ./check-prerequisites.sh --workspace-info
  
  # Generate specs index (rollup)
  ./check-prerequisites.sh --rollup
  
  # List all specs from index
  ./check-prerequisites.sh --list-specs
  
  # List specs as JSON
  ./check-prerequisites.sh --list-specs --json
  
EOF
            exit 0
            ;;
        -*)
            echo "ERROR: Unknown option '$1'. Use --help for usage information." >&2
            exit 1
            ;;
        *)
            # Positional argument - treat as feature shorthand
            if [[ -z "$FEATURE_SHORTHAND" ]]; then
                FEATURE_SHORTHAND="$1"
            else
                echo "ERROR: Multiple positional arguments provided. Only one feature shorthand allowed." >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Source common functions
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Handle feature shorthand if provided (must be done before workspace-level commands)
RESOLVED_FEATURE_DIR=""
RESOLVED_SOURCE_DIR=""
RESOLVED_SOURCE_INFO=""
if [[ -n "$FEATURE_SHORTHAND" ]]; then
    if ! is_workspace_mode; then
        echo "ERROR: Feature shorthand ($FEATURE_SHORTHAND) only works in workspace mode" >&2
        echo "Initialize workspace with: specify workspace --here" >&2
        exit 1
    fi
    
    # Parse and validate the feature shorthand
    shorthand_result=$(parse_feature_shorthand "$FEATURE_SHORTHAND" 2>&1) || {
        eval "$shorthand_result"
        exit 1
    }
    eval "$shorthand_result"
    
    # Validate project exists in workspace
    projects=$(list_projects 2>/dev/null || true)
    if ! echo "$projects" | grep -qx "$SHORTHAND_PROJECT"; then
        echo "ERROR: Invalid project '$SHORTHAND_PROJECT' in shorthand '$FEATURE_SHORTHAND'" >&2
        echo "" >&2
        echo "Available projects:" >&2
        echo "$projects" | sed 's/^/  - /' >&2
        exit 1
    fi
    
    # Set SPECIFY_FEATURE and capture the resolved directory for direct use
    export SPECIFY_FEATURE="$SHORTHAND_FEATURE_NAME"
    RESOLVED_FEATURE_DIR="$SHORTHAND_FEATURE_DIR"
    
    # Resolve source directory (where actual code changes should be made)
    source_result=$(resolve_source_dir "$SHORTHAND_PROJECT" "$SHORTHAND_FEATURE_NAME" 2>/dev/null) || true
    if [[ -n "$source_result" ]]; then
        eval "$source_result"
        RESOLVED_SOURCE_DIR="$SOURCE_DIR"
        RESOLVED_SOURCE_INFO="$source_result"
    fi
fi

# Handle workspace-level commands (don't require feature context)
if $LIST_PROJECTS; then
    if ! is_workspace_mode; then
        echo "ERROR: --list-projects only works in workspace mode" >&2
        echo "Initialize workspace with: specify workspace --here" >&2
        exit 1
    fi
    
    projects=$(list_projects)
    if [[ -z "$projects" ]]; then
        echo "No projects found in workspace" >&2
        exit 1
    fi
    
    if $JSON_MODE; then
        printf '['
        first=true
        while IFS= read -r project; do
            if $first; then
                first=false
            else
                printf ','
            fi
            printf '"%s"' "$project"
        done <<< "$projects"
        printf ']\n'
    else
        echo "$projects"
    fi
    exit 0
fi

if $LIST_PROJECTS_DETAILED; then
    if ! is_workspace_mode; then
        echo "ERROR: --list-projects-detailed only works in workspace mode" >&2
        echo "Initialize workspace with: specify workspace --here" >&2
        exit 1
    fi
    
    workspace_root=$(get_workspace_root)
    
    if $JSON_MODE; then
        printf '{"workspace_root":"%s","projects":[' "$workspace_root"
        first=true
        while IFS=$'\t' read -r name has_git remote_url branch is_worktree main_worktree; do
            if $first; then
                first=false
            else
                printf ','
            fi
            printf '{"name":"%s","has_git":%s,"remote_url":"%s","branch":"%s","is_worktree":%s,"main_worktree":"%s"}' \
                "$name" "$has_git" "$remote_url" "$branch" "$is_worktree" "$main_worktree"
        done < <(list_projects_detailed)
        printf ']}\n'
    else
        echo "Workspace: $workspace_root"
        echo ""
        printf "%-40s %-8s %-10s %-20s %s\n" "PROJECT" "GIT" "WORKTREE" "BRANCH" "REMOTE"
        printf "%-40s %-8s %-10s %-20s %s\n" "-------" "---" "--------" "------" "------"
        while IFS=$'\t' read -r name has_git remote_url branch is_worktree main_worktree; do
            git_status="no"
            wt_status="-"
            br="$branch"
            rm="$remote_url"
            
            if [[ "$has_git" == "true" ]]; then
                git_status="yes"
                if [[ "$is_worktree" == "true" ]]; then
                    wt_status="of:$main_worktree"
                fi
            else
                br="-"
                rm="-"
            fi
            
            printf "%-40s %-8s %-10s %-20s %s\n" "$name" "$git_status" "$wt_status" "$br" "$rm"
        done < <(list_projects_detailed)
    fi
    exit 0
fi

if $ROLLUP; then
    if ! is_workspace_mode; then
        echo "ERROR: --rollup only works in workspace mode" >&2
        echo "Initialize workspace with: specify workspace --here" >&2
        exit 1
    fi
    
    include_wt="false"
    [[ "$INCLUDE_WORKTREES" == "true" ]] && include_wt="true"
    
    spec_count=$(generate_specs_index "$include_wt")
    
    if $JSON_MODE; then
        read_specs_index
    else
        workspace_root=$(get_workspace_root)
        echo "Workspace: $workspace_root"
        echo "Specs indexed: $spec_count"
        echo "Index files:"
        echo "  - .specify/specs-index.json"
        echo "  - .specify/specs-index.md"
    fi
    exit 0
fi

if $LIST_SPECS; then
    if ! is_workspace_mode; then
        echo "ERROR: --list-specs only works in workspace mode" >&2
        echo "Initialize workspace with: specify workspace --here" >&2
        exit 1
    fi
    
    workspace_root=$(get_workspace_root)
    index_file="$workspace_root/.specify/specs-index.json"
    
    if [[ ! -f "$index_file" ]] || $FORCE_REFRESH; then
        include_wt="false"
        [[ "$INCLUDE_WORKTREES" == "true" ]] && include_wt="true"
        generate_specs_index "$include_wt" >/dev/null
    fi
    
    if $JSON_MODE; then
        read_specs_index
    else
        echo "Workspace: $workspace_root"
        echo ""
        printf "%-30s %-35s %-6s %-6s %-6s %s\n" "PROJECT" "FEATURE" "SPEC" "PLAN" "TASKS" "BRANCH"
        printf "%-30s %-35s %-6s %-6s %-6s %s\n" "-------" "-------" "----" "----" "-----" "------"
        
        if command -v jq >/dev/null 2>&1; then
            jq -r '.specs[] | [.project, .feature, (if .has_spec then "✓" else "-" end), (if .has_plan then "✓" else "-" end), (if .has_tasks then "✓" else "-" end), .branch] | @tsv' "$index_file" | \
            while IFS=$'\t' read -r project feature has_spec has_plan has_tasks branch; do
                printf "%-30s %-35s %-6s %-6s %-6s %s\n" "$project" "$feature" "$has_spec" "$has_plan" "$has_tasks" "$branch"
            done
        else
            cat "$workspace_root/.specify/specs-index.md"
        fi
    fi
    exit 0
fi

if $LIST_FEATURES; then
    if ! is_workspace_mode; then
        echo "ERROR: --list-features only works in workspace mode" >&2
        echo "Initialize workspace with: specify workspace --here" >&2
        exit 1
    fi
    
    if $JSON_MODE; then
        specs_dir=$(get_specs_dir)
        if [[ ! -d "$specs_dir" ]]; then
            printf '[]\n'
            exit 0
        fi
        
        printf '['
        first=true
        for project_dir in "$specs_dir"/*/; do
            [[ -d "$project_dir" ]] || continue
            project=$(basename "$project_dir")
            
            for feature_dir in "$project_dir"/*; do
                [[ -d "$feature_dir" ]] || continue
                feature=$(basename "$feature_dir")
                
                if [[ "$feature" =~ ^([0-9]{3})- ]]; then
                    num="${BASH_REMATCH[1]}"
                    if $first; then
                        first=false
                    else
                        printf ','
                    fi
                    printf '"%s-%s"' "$project" "$num"
                fi
            done
        done
        printf ']\n'
    else
        list_workspace_features
    fi
    exit 0
fi

if $WORKSPACE_INFO; then
    workspace_mode="false"
    workspace_root=""
    projects_json="[]"
    features_json="[]"
    
    if is_workspace_mode; then
        workspace_mode="true"
        workspace_root=$(get_workspace_root)
        
        # Get projects as JSON array
        projects=$(list_projects 2>/dev/null || true)
        if [[ -n "$projects" ]]; then
            projects_json='['
            first=true
            while IFS= read -r project; do
                if $first; then
                    first=false
                else
                    projects_json+=','
                fi
                projects_json+="\"$project\""
            done <<< "$projects"
            projects_json+=']'
        fi
        
        # Get features by scanning specs directory directly
        specs_dir=$(get_specs_dir)
        if [[ -d "$specs_dir" ]]; then
            features_json='['
            first=true
            for project_dir in "$specs_dir"/*/; do
                [[ -d "$project_dir" ]] || continue
                local project=$(basename "$project_dir")
                
                for feature_dir in "$project_dir"/*; do
                    [[ -d "$feature_dir" ]] || continue
                    local feature=$(basename "$feature_dir")
                    
                    if [[ "$feature" =~ ^([0-9]{3})- ]]; then
                        local num="${BASH_REMATCH[1]}"
                        if $first; then
                            first=false
                        else
                            features_json+=','
                        fi
                        features_json+="\"$project-$num\""
                    fi
                done
            done
            features_json+=']'
        fi
    fi
    
    printf '{"workspace_mode":%s,"workspace_root":"%s","projects":%s,"features":%s}\n' \
        "$workspace_mode" "$workspace_root" "$projects_json" "$features_json"
    exit 0
fi

# Get feature paths and validate branch
eval $(get_feature_paths)

# Override with resolved feature directory if shorthand was used
if [[ -n "$RESOLVED_FEATURE_DIR" ]]; then
    FEATURE_DIR="$RESOLVED_FEATURE_DIR"
    FEATURE_SPEC="$FEATURE_DIR/spec.md"
    IMPL_PLAN="$FEATURE_DIR/plan.md"
    TASKS="$FEATURE_DIR/tasks.md"
    RESEARCH="$FEATURE_DIR/research.md"
    DATA_MODEL="$FEATURE_DIR/data-model.md"
    QUICKSTART="$FEATURE_DIR/quickstart.md"
    CONTRACTS_DIR="$FEATURE_DIR/contracts"
fi

check_feature_branch "$CURRENT_BRANCH" "$HAS_GIT" || exit 1

# If paths-only mode, output paths and exit (support JSON + paths-only combined)
if $PATHS_ONLY; then
    if $JSON_MODE; then
        if [[ -n "$RESOLVED_SOURCE_DIR" ]]; then
            eval "$RESOLVED_SOURCE_INFO"
            printf '{"REPO_ROOT":"%s","BRANCH":"%s","SPEC_DIR":"%s","SOURCE_DIR":"%s","SOURCE_BRANCH":"%s","IS_WORKTREE":%s,"FEATURE_SPEC":"%s","IMPL_PLAN":"%s","TASKS":"%s"}\n' \
                "$REPO_ROOT" "$CURRENT_BRANCH" "$FEATURE_DIR" "$SOURCE_DIR" "$SOURCE_BRANCH" "$IS_WORKTREE" "$FEATURE_SPEC" "$IMPL_PLAN" "$TASKS"
        else
            printf '{"REPO_ROOT":"%s","BRANCH":"%s","FEATURE_DIR":"%s","FEATURE_SPEC":"%s","IMPL_PLAN":"%s","TASKS":"%s"}\n' \
                "$REPO_ROOT" "$CURRENT_BRANCH" "$FEATURE_DIR" "$FEATURE_SPEC" "$IMPL_PLAN" "$TASKS"
        fi
    else
        echo "REPO_ROOT: $REPO_ROOT"
        echo "BRANCH: $CURRENT_BRANCH"
        echo "SPEC_DIR: $FEATURE_DIR"
        if [[ -n "$RESOLVED_SOURCE_DIR" ]]; then
            eval "$RESOLVED_SOURCE_INFO"
            echo "SOURCE_DIR: $SOURCE_DIR"
            echo "SOURCE_BRANCH: $SOURCE_BRANCH"
            echo "IS_WORKTREE: $IS_WORKTREE"
        fi
        echo "FEATURE_SPEC: $FEATURE_SPEC"
        echo "IMPL_PLAN: $IMPL_PLAN"
        echo "TASKS: $TASKS"
    fi
    exit 0
fi

# Validate required directories and files
if [[ ! -d "$FEATURE_DIR" ]]; then
    echo "ERROR: Feature directory not found: $FEATURE_DIR" >&2
    echo "Run /speckit.specify first to create the feature structure." >&2
    exit 1
fi

if [[ ! -f "$IMPL_PLAN" ]]; then
    echo "ERROR: plan.md not found in $FEATURE_DIR" >&2
    echo "Run /speckit.plan first to create the implementation plan." >&2
    exit 1
fi

# Check for tasks.md if required
if $REQUIRE_TASKS && [[ ! -f "$TASKS" ]]; then
    echo "ERROR: tasks.md not found in $FEATURE_DIR" >&2
    echo "Run /speckit.tasks first to create the task list." >&2
    exit 1
fi

# Build list of available documents
docs=()

# Always check these optional docs
[[ -f "$RESEARCH" ]] && docs+=("research.md")
[[ -f "$DATA_MODEL" ]] && docs+=("data-model.md")

# Check contracts directory (only if it exists and has files)
if [[ -d "$CONTRACTS_DIR" ]] && [[ -n "$(ls -A "$CONTRACTS_DIR" 2>/dev/null)" ]]; then
    docs+=("contracts/")
fi

[[ -f "$QUICKSTART" ]] && docs+=("quickstart.md")

# Include tasks.md if requested and it exists
if $INCLUDE_TASKS && [[ -f "$TASKS" ]]; then
    docs+=("tasks.md")
fi

# Output results
if $JSON_MODE; then
    if [[ ${#docs[@]} -eq 0 ]]; then
        json_docs="[]"
    else
        json_docs=$(printf '"%s",' "${docs[@]}")
        json_docs="[${json_docs%,}]"
    fi
    
    # Include source directory info if resolved (workspace mode with feature shorthand)
    if [[ -n "$RESOLVED_SOURCE_DIR" ]]; then
        eval "$RESOLVED_SOURCE_INFO"
        printf '{"SPEC_DIR":"%s","SOURCE_DIR":"%s","SOURCE_BRANCH":"%s","IS_WORKTREE":%s,"EXPECTED_BRANCH":"%s","BRANCH_STATUS":"%s","AVAILABLE_DOCS":%s}\n' \
            "$FEATURE_DIR" "$SOURCE_DIR" "$SOURCE_BRANCH" "$IS_WORKTREE" "$EXPECTED_BRANCH" "$BRANCH_STATUS" "$json_docs"
    else
        # Legacy output format (backward compatible)
        printf '{"FEATURE_DIR":"%s","AVAILABLE_DOCS":%s}\n' "$FEATURE_DIR" "$json_docs"
    fi
else
    echo "SPEC_DIR: $FEATURE_DIR"
    
    if [[ -n "$RESOLVED_SOURCE_DIR" ]]; then
        eval "$RESOLVED_SOURCE_INFO"
        echo "SOURCE_DIR: $SOURCE_DIR"
        echo "SOURCE_BRANCH: $SOURCE_BRANCH"
        echo "IS_WORKTREE: $IS_WORKTREE"
        if [[ "$BRANCH_STATUS" == "switch_needed" ]]; then
            echo "WARNING: Source directory is on branch '$SOURCE_BRANCH', expected '$EXPECTED_BRANCH'"
        fi
    fi
    
    echo "AVAILABLE_DOCS:"
    check_file "$RESEARCH" "research.md"
    check_file "$DATA_MODEL" "data-model.md"
    check_dir "$CONTRACTS_DIR" "contracts/"
    check_file "$QUICKSTART" "quickstart.md"
    
    if $INCLUDE_TASKS; then
        check_file "$TASKS" "tasks.md"
    fi
fi
