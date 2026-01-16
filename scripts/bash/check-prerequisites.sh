#!/usr/bin/env bash

# Consolidated prerequisite checking script
#
# This script provides unified prerequisite checking for Spec-Driven Development workflow.
# It replaces the functionality previously spread across multiple scripts.
#
# Usage: ./check-prerequisites.sh [OPTIONS]
#
# OPTIONS:
#   --json              Output in JSON format
#   --require-tasks     Require tasks.md to exist (for implementation phase)
#   --include-tasks     Include tasks.md in AVAILABLE_DOCS list
#   --paths-only        Only output path variables (no validation)
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
WORKSPACE_INFO=false

for arg in "$@"; do
    case "$arg" in
        --json)
            JSON_MODE=true
            ;;
        --require-tasks)
            REQUIRE_TASKS=true
            ;;
        --include-tasks)
            INCLUDE_TASKS=true
            ;;
        --paths-only)
            PATHS_ONLY=true
            ;;
        --list-projects)
            LIST_PROJECTS=true
            ;;
        --workspace-info)
            WORKSPACE_INFO=true
            ;;
        --help|-h)
            cat << 'EOF'
Usage: check-prerequisites.sh [OPTIONS]

Consolidated prerequisite checking for Spec-Driven Development workflow.

OPTIONS:
  --json              Output in JSON format
  --require-tasks     Require tasks.md to exist (for implementation phase)
  --include-tasks     Include tasks.md in AVAILABLE_DOCS list
  --paths-only        Only output path variables (no prerequisite validation)
  --list-projects     List available projects in workspace mode
  --workspace-info    Output workspace context (projects, features, mode) as JSON
  --help, -h          Show this help message

EXAMPLES:
  # Check task prerequisites (plan.md required)
  ./check-prerequisites.sh --json
  
  # Check implementation prerequisites (plan.md + tasks.md required)
  ./check-prerequisites.sh --json --require-tasks --include-tasks
  
  # Get feature paths only (no validation)
  ./check-prerequisites.sh --paths-only
  
  # List available projects in workspace
  ./check-prerequisites.sh --list-projects
  
  # Get full workspace context for AI agents
  ./check-prerequisites.sh --workspace-info
  
EOF
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option '$arg'. Use --help for usage information." >&2
            exit 1
            ;;
    esac
done

# Source common functions
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

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
        # Output as JSON array
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
check_feature_branch "$CURRENT_BRANCH" "$HAS_GIT" || exit 1

# If paths-only mode, output paths and exit (support JSON + paths-only combined)
if $PATHS_ONLY; then
    if $JSON_MODE; then
        # Minimal JSON paths payload (no validation performed)
        printf '{"REPO_ROOT":"%s","BRANCH":"%s","FEATURE_DIR":"%s","FEATURE_SPEC":"%s","IMPL_PLAN":"%s","TASKS":"%s"}\n' \
            "$REPO_ROOT" "$CURRENT_BRANCH" "$FEATURE_DIR" "$FEATURE_SPEC" "$IMPL_PLAN" "$TASKS"
    else
        echo "REPO_ROOT: $REPO_ROOT"
        echo "BRANCH: $CURRENT_BRANCH"
        echo "FEATURE_DIR: $FEATURE_DIR"
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
    # Build JSON array of documents
    if [[ ${#docs[@]} -eq 0 ]]; then
        json_docs="[]"
    else
        json_docs=$(printf '"%s",' "${docs[@]}")
        json_docs="[${json_docs%,}]"
    fi
    
    printf '{"FEATURE_DIR":"%s","AVAILABLE_DOCS":%s}\n' "$FEATURE_DIR" "$json_docs"
else
    # Text output
    echo "FEATURE_DIR:$FEATURE_DIR"
    echo "AVAILABLE_DOCS:"
    
    # Show status of each potential document
    check_file "$RESEARCH" "research.md"
    check_file "$DATA_MODEL" "data-model.md"
    check_dir "$CONTRACTS_DIR" "contracts/"
    check_file "$QUICKSTART" "quickstart.md"
    
    if $INCLUDE_TASKS; then
        check_file "$TASKS" "tasks.md"
    fi
fi
