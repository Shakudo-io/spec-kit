#!/usr/bin/env bash

set -e

JSON_MODE=false
FEATURE_SHORTHAND=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) 
            JSON_MODE=true 
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
            echo "Usage: $0 [--json] [--feature <shorthand>] [feature-shorthand]"
            echo ""
            echo "OPTIONS:"
            echo "  --json              Output results in JSON format"
            echo "  --feature <ref>     Feature shorthand (e.g., monorepo-001)"
            echo "  --help              Show this help message"
            echo ""
            echo "EXAMPLES:"
            echo "  $0 --json monorepo-001"
            echo "  $0 --json --feature backend-api-002"
            exit 0 
            ;;
        -*)
            echo "ERROR: Unknown option '$1'. Use --help for usage information." >&2
            exit 1
            ;;
        *) 
            if [[ -z "$FEATURE_SHORTHAND" ]]; then
                FEATURE_SHORTHAND="$1"
            else
                echo "ERROR: Multiple positional arguments provided." >&2
                exit 1
            fi
            shift
            ;;
    esac
done

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Handle feature shorthand if provided
if [[ -n "$FEATURE_SHORTHAND" ]]; then
    if ! is_workspace_mode; then
        echo "ERROR: Feature shorthand ($FEATURE_SHORTHAND) only works in workspace mode" >&2
        exit 1
    fi
    
    shorthand_result=$(parse_feature_shorthand "$FEATURE_SHORTHAND" 2>&1) || {
        eval "$shorthand_result"
        exit 1
    }
    eval "$shorthand_result"
    
    # Validate project exists
    projects=$(list_projects 2>/dev/null || true)
    if ! echo "$projects" | grep -qx "$SHORTHAND_PROJECT"; then
        echo "ERROR: Invalid project '$SHORTHAND_PROJECT' in shorthand '$FEATURE_SHORTHAND'" >&2
        echo "" >&2
        echo "Available projects:" >&2
        echo "$projects" | sed 's/^/  - /' >&2
        exit 1
    fi
    
    export SPECIFY_FEATURE="$SHORTHAND_FEATURE_NAME"
fi

eval $(get_feature_paths)

# Check if we're on a proper feature branch (only for git repos)
check_feature_branch "$CURRENT_BRANCH" "$HAS_GIT" || exit 1

# Ensure the feature directory exists
mkdir -p "$FEATURE_DIR"

# Copy plan template if it exists
TEMPLATE="$REPO_ROOT/.specify/templates/plan-template.md"
if [[ -f "$TEMPLATE" ]]; then
    cp "$TEMPLATE" "$IMPL_PLAN"
    echo "Copied plan template to $IMPL_PLAN"
else
    echo "Warning: Plan template not found at $TEMPLATE"
    # Create a basic plan file if template doesn't exist
    touch "$IMPL_PLAN"
fi

# Output results
if $JSON_MODE; then
    printf '{"FEATURE_SPEC":"%s","IMPL_PLAN":"%s","SPECS_DIR":"%s","BRANCH":"%s","HAS_GIT":"%s"}\n' \
        "$FEATURE_SPEC" "$IMPL_PLAN" "$FEATURE_DIR" "$CURRENT_BRANCH" "$HAS_GIT"
else
    echo "FEATURE_SPEC: $FEATURE_SPEC"
    echo "IMPL_PLAN: $IMPL_PLAN" 
    echo "SPECS_DIR: $FEATURE_DIR"
    echo "BRANCH: $CURRENT_BRANCH"
    echo "HAS_GIT: $HAS_GIT"
fi

