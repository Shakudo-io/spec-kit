#!/usr/bin/env bash
#
# create-new-feature.sh - Create a new feature branch with spec directory
#
# Version: 2.0.0 - Multi-repository workspace support
#
# Usage:
#   ./create-new-feature.sh [OPTIONS] <feature_description>
#
# Options:
#   --project <name>      Target project/repo name (REQUIRED in workspace mode)
#   --short-name <name>   Custom branch name suffix (2-4 words)
#   --number <N>          Specify branch number manually
#   --json                Output in JSON format
#   --help, -h            Show help
#
# Examples:
#   # Workspace mode (multi-repo)
#   ./create-new-feature.sh --project monorepo "Add cost estimation feature"
#
#   # Legacy mode (single repo)
#   ./create-new-feature.sh "Add user authentication"

set -e

# Source common functions
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

JSON_MODE=false
SHORT_NAME=""
BRANCH_NUMBER=""
PROJECT_NAME=""
ARGS=()

i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
        --json) 
            JSON_MODE=true 
            ;;
        --project)
            if [ $((i + 1)) -gt $# ]; then
                echo 'Error: --project requires a value' >&2
                exit 1
            fi
            i=$((i + 1))
            next_arg="${!i}"
            if [[ "$next_arg" == --* ]]; then
                echo 'Error: --project requires a value' >&2
                exit 1
            fi
            PROJECT_NAME="$next_arg"
            ;;
        --short-name)
            if [ $((i + 1)) -gt $# ]; then
                echo 'Error: --short-name requires a value' >&2
                exit 1
            fi
            i=$((i + 1))
            next_arg="${!i}"
            if [[ "$next_arg" == --* ]]; then
                echo 'Error: --short-name requires a value' >&2
                exit 1
            fi
            SHORT_NAME="$next_arg"
            ;;
        --number)
            if [ $((i + 1)) -gt $# ]; then
                echo 'Error: --number requires a value' >&2
                exit 1
            fi
            i=$((i + 1))
            next_arg="${!i}"
            if [[ "$next_arg" == --* ]]; then
                echo 'Error: --number requires a value' >&2
                exit 1
            fi
            BRANCH_NUMBER="$next_arg"
            ;;
        --help|-h) 
            cat << 'EOF'
Usage: create-new-feature.sh [OPTIONS] <feature_description>

Create a new feature branch with spec directory structure.

OPTIONS:
  --project <name>      Target project/repo name (REQUIRED in workspace mode)
  --short-name <name>   Custom branch name suffix (2-4 words)
  --number <N>          Specify branch number manually
  --json                Output in JSON format
  --help, -h            Show this help

WORKSPACE MODE (multi-repo):
  When a workspace.yaml exists, you must specify --project:
  
  ./create-new-feature.sh --project monorepo "Add feature" --short-name my-feature
  
  Creates:
    - Branch: monorepo-001-my-feature (in monorepo repo)
    - Specs: {workspace}/specs/monorepo/001-my-feature/

LEGACY MODE (single repo):
  Without workspace.yaml, works in current repo:
  
  ./create-new-feature.sh "Add feature" --short-name my-feature
  
  Creates:
    - Branch: 001-my-feature
    - Specs: ./specs/001-my-feature/

ENVIRONMENT VARIABLES:
  SPECIFY_PROJECT    - Default project name (alternative to --project)
  SPECIFY_WORKSPACE  - Override workspace root detection

EXAMPLES:
  # Create feature in monorepo project
  ./create-new-feature.sh --project monorepo "User authentication system" --short-name user-auth

  # With explicit number
  ./create-new-feature.sh --project business-automation "Recruiting pipeline" --number 5

  # JSON output for scripting
  ./create-new-feature.sh --project monorepo --json "Cost estimation"
EOF
            exit 0
            ;;
        *) 
            ARGS+=("$arg") 
            ;;
    esac
    i=$((i + 1))
done

FEATURE_DESCRIPTION="${ARGS[*]}"
if [ -z "$FEATURE_DESCRIPTION" ]; then
    echo "Error: Feature description required" >&2
    echo "Usage: $0 [--project <name>] [--json] [--short-name <name>] [--number N] <feature_description>" >&2
    exit 1
fi

# =============================================================================
# WORKSPACE/PROJECT DETECTION
# =============================================================================

WORKSPACE_MODE=false
WORKSPACE_ROOT=""
PROJECT_ROOT=""
HAS_GIT=false

if is_workspace_mode; then
    WORKSPACE_MODE=true
    WORKSPACE_ROOT=$(get_workspace_root)
    
    # In workspace mode, project is required
    if [ -z "$PROJECT_NAME" ]; then
        # Try to get from environment
        PROJECT_NAME="${SPECIFY_PROJECT:-}"
    fi
    
    if [ -z "$PROJECT_NAME" ]; then
        # Try to detect from current directory
        if git rev-parse --show-toplevel >/dev/null 2>&1; then
            PROJECT_ROOT=$(git rev-parse --show-toplevel)
            PROJECT_NAME=$(basename "$PROJECT_ROOT")
        fi
    fi
    
    if [ -z "$PROJECT_NAME" ]; then
        echo "Error: --project <name> is required in workspace mode" >&2
        echo "" >&2
        echo "Available projects:" >&2
        list_projects | sed 's/^/  - /' >&2
        echo "" >&2
        echo "Usage: $0 --project <name> <feature_description>" >&2
        exit 1
    fi
    
    # Resolve project root
    PROJECT_ROOT="$WORKSPACE_ROOT/$PROJECT_NAME"
    if [ ! -d "$PROJECT_ROOT" ]; then
        echo "Error: Project '$PROJECT_NAME' not found at $PROJECT_ROOT" >&2
        echo "" >&2
        echo "Available projects:" >&2
        list_projects | sed 's/^/  - /' >&2
        exit 1
    fi
    
    # Check if project is a git repo
    if [ -d "$PROJECT_ROOT/.git" ] || git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        HAS_GIT=true
    fi
    
    # Export for common.sh functions
    export SPECIFY_PROJECT="$PROJECT_NAME"
    export SPECIFY_PROJECT_ROOT="$PROJECT_ROOT"
    export SPECIFY_WORKSPACE="$WORKSPACE_ROOT"
else
    # Legacy single-repo mode
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
        PROJECT_ROOT=$(git rev-parse --show-toplevel)
        HAS_GIT=true
    else
        # Fall back to searching for repo markers
        PROJECT_ROOT=$(find_repo_root_legacy "$SCRIPT_DIR")
        if [ -z "$PROJECT_ROOT" ]; then
            echo "Error: Could not determine repository root." >&2
            exit 1
        fi
    fi
    PROJECT_NAME=$(basename "$PROJECT_ROOT")
fi

# =============================================================================
# SPECS DIRECTORY SETUP
# =============================================================================

if [ "$WORKSPACE_MODE" = true ]; then
    # Centralized specs at workspace/specs/project/
    SPECS_BASE=$(get_specs_dir)
    SPECS_DIR="$SPECS_BASE/$PROJECT_NAME"
else
    # Legacy: specs in repo root
    SPECS_DIR="$PROJECT_ROOT/specs"
fi

mkdir -p "$SPECS_DIR"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Legacy function for non-workspace root finding
find_repo_root_legacy() {
    local dir="$1"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.git" ] || [ -d "$dir/.specify" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# Get highest number from specs directory
get_highest_from_specs() {
    local specs_dir="$1"
    local project_prefix="$2"
    local highest=0
    
    if [ -d "$specs_dir" ]; then
        for dir in "$specs_dir"/*; do
            [ -d "$dir" ] || continue
            dirname=$(basename "$dir")
            
            # Match both formats: 001-feature and project-001-feature
            if [ -n "$project_prefix" ]; then
                # Try project-prefixed format first
                if [[ "$dirname" =~ ^${project_prefix}-([0-9]{3})- ]]; then
                    number=$((10#${BASH_REMATCH[1]}))
                    [ "$number" -gt "$highest" ] && highest=$number
                    continue
                fi
            fi
            
            # Try standard format
            if [[ "$dirname" =~ ^([0-9]{3})- ]]; then
                number=$((10#${BASH_REMATCH[1]}))
                [ "$number" -gt "$highest" ] && highest=$number
            fi
        done
    fi
    
    echo "$highest"
}

# Get highest number from git branches
get_highest_from_branches() {
    local repo_dir="$1"
    local project_prefix="$2"
    local highest=0
    
    # Fetch remotes
    git -C "$repo_dir" fetch --all --prune 2>/dev/null || true
    
    # Get all branches
    local branches
    branches=$(git -C "$repo_dir" branch -a 2>/dev/null || echo "")
    
    if [ -n "$branches" ]; then
        while IFS= read -r branch; do
            # Clean branch name
            clean_branch=$(echo "$branch" | sed 's/^[* ]*//; s|^remotes/[^/]*/||')
            
            if [ -n "$project_prefix" ]; then
                # Try project-prefixed format: project-001-feature
                if [[ "$clean_branch" =~ ^${project_prefix}-([0-9]{3})- ]]; then
                    number=$((10#${BASH_REMATCH[1]}))
                    [ "$number" -gt "$highest" ] && highest=$number
                    continue
                fi
            fi
            
            # Try standard format: 001-feature
            if [[ "$clean_branch" =~ ^([0-9]{3})- ]]; then
                number=$((10#${BASH_REMATCH[1]}))
                [ "$number" -gt "$highest" ] && highest=$number
            fi
        done <<< "$branches"
    fi
    
    echo "$highest"
}

# Get next available feature number
get_next_feature_number() {
    local project_prefix=""
    [ "$WORKSPACE_MODE" = true ] && project_prefix="$PROJECT_NAME"
    
    local highest_spec=0
    local highest_branch=0
    
    # Check specs directory
    highest_spec=$(get_highest_from_specs "$SPECS_DIR" "$project_prefix")
    
    # Check git branches if available
    if [ "$HAS_GIT" = true ]; then
        highest_branch=$(get_highest_from_branches "$PROJECT_ROOT" "$project_prefix")
    fi
    
    # Return max + 1
    local max=$highest_spec
    # Ensure highest_branch is a number before comparison
    if [ -n "$highest_branch" ] && [ "$highest_branch" -gt "$max" ] 2>/dev/null; then
        max=$highest_branch
    fi
    
    echo $((max + 1))
}

# Clean and format a branch name
clean_branch_name() {
    local name="$1"
    echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//' | sed 's/-$//'
}

# Generate branch name with stop word filtering
generate_branch_name() {
    local description="$1"
    
    local stop_words="^(i|a|an|the|to|for|of|in|on|at|by|with|from|is|are|was|were|be|been|being|have|has|had|do|does|did|will|would|should|could|can|may|might|must|shall|this|that|these|those|my|your|our|their|want|need|add|get|set|build|create|implement|develop)$"
    
    local clean_name=$(echo "$description" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/ /g')
    local meaningful_words=()
    
    for word in $clean_name; do
        [ -z "$word" ] && continue
        if ! echo "$word" | grep -qiE "$stop_words"; then
            if [ ${#word} -ge 3 ]; then
                meaningful_words+=("$word")
            fi
        fi
    done
    
    if [ ${#meaningful_words[@]} -gt 0 ]; then
        local max_words=3
        [ ${#meaningful_words[@]} -eq 4 ] && max_words=4
        
        local result=""
        local count=0
        for word in "${meaningful_words[@]}"; do
            [ $count -ge $max_words ] && break
            [ -n "$result" ] && result="$result-"
            result="$result$word"
            count=$((count + 1))
        done
        echo "$result"
    else
        clean_branch_name "$description" | tr '-' '\n' | grep -v '^$' | head -3 | tr '\n' '-' | sed 's/-$//'
    fi
}

# =============================================================================
# BRANCH NAME GENERATION
# =============================================================================

# Generate branch suffix from description or short-name
if [ -n "$SHORT_NAME" ]; then
    BRANCH_SUFFIX=$(clean_branch_name "$SHORT_NAME")
else
    BRANCH_SUFFIX=$(generate_branch_name "$FEATURE_DESCRIPTION")
fi

# Determine branch number
if [ -z "$BRANCH_NUMBER" ]; then
    BRANCH_NUMBER=$(get_next_feature_number)
fi

# Format feature number with leading zeros
FEATURE_NUM=$(printf "%03d" "$((10#$BRANCH_NUMBER))")

# Build branch name based on mode
if [ "$WORKSPACE_MODE" = true ]; then
    # Workspace mode: project-001-feature
    BRANCH_NAME="${PROJECT_NAME}-${FEATURE_NUM}-${BRANCH_SUFFIX}"
    SPEC_DIR_NAME="${FEATURE_NUM}-${BRANCH_SUFFIX}"
else
    # Legacy mode: 001-feature
    BRANCH_NAME="${FEATURE_NUM}-${BRANCH_SUFFIX}"
    SPEC_DIR_NAME="$BRANCH_NAME"
fi

# Validate branch name length (GitHub limit: 244 bytes)
MAX_BRANCH_LENGTH=244
if [ ${#BRANCH_NAME} -gt $MAX_BRANCH_LENGTH ]; then
    ORIGINAL_BRANCH_NAME="$BRANCH_NAME"
    
    if [ "$WORKSPACE_MODE" = true ]; then
        # Account for: project- + feature number (3) + hyphen (1)
        PREFIX_LEN=$((${#PROJECT_NAME} + 5))
        MAX_SUFFIX_LENGTH=$((MAX_BRANCH_LENGTH - PREFIX_LEN))
    else
        # Account for: feature number (3) + hyphen (1) = 4 chars
        MAX_SUFFIX_LENGTH=$((MAX_BRANCH_LENGTH - 4))
    fi
    
    TRUNCATED_SUFFIX=$(echo "$BRANCH_SUFFIX" | cut -c1-$MAX_SUFFIX_LENGTH | sed 's/-$//')
    
    if [ "$WORKSPACE_MODE" = true ]; then
        BRANCH_NAME="${PROJECT_NAME}-${FEATURE_NUM}-${TRUNCATED_SUFFIX}"
    else
        BRANCH_NAME="${FEATURE_NUM}-${TRUNCATED_SUFFIX}"
    fi
    
    SPEC_DIR_NAME="${FEATURE_NUM}-${TRUNCATED_SUFFIX}"
    
    >&2 echo "[specify] Warning: Branch name exceeded 244-byte limit"
    >&2 echo "[specify] Truncated: $ORIGINAL_BRANCH_NAME -> $BRANCH_NAME"
fi

# =============================================================================
# CREATE BRANCH AND SPEC DIRECTORY
# =============================================================================

# Change to project directory for git operations
cd "$PROJECT_ROOT"

# Create branch
if [ "$HAS_GIT" = true ]; then
    # Check if branch already exists
    if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
        >&2 echo "[specify] Branch $BRANCH_NAME already exists, switching to it"
        git checkout "$BRANCH_NAME"
    else
        git checkout -b "$BRANCH_NAME"
    fi
else
    >&2 echo "[specify] Warning: Git not available; skipped branch creation for $BRANCH_NAME"
fi

# Create spec directory
FEATURE_DIR="$SPECS_DIR/$SPEC_DIR_NAME"
mkdir -p "$FEATURE_DIR"

# Copy spec template - check multiple locations
TEMPLATE=""
if [ "$WORKSPACE_MODE" = true ]; then
    # Workspace mode: check multiple template locations
    for tpl_path in \
        "$WORKSPACE_ROOT/.specify/templates/spec-template.md" \
        "$WORKSPACE_ROOT/templates/spec-template.md" \
        "$SCRIPT_DIR/../../templates/spec-template.md"; do
        if [ -f "$tpl_path" ]; then
            TEMPLATE="$tpl_path"
            break
        fi
    done
else
    # Legacy mode: check project template locations
    for tpl_path in \
        "$PROJECT_ROOT/.specify/templates/spec-template.md" \
        "$PROJECT_ROOT/templates/spec-template.md"; do
        if [ -f "$tpl_path" ]; then
            TEMPLATE="$tpl_path"
            break
        fi
    done
fi

SPEC_FILE="$FEATURE_DIR/spec.md"
if [ -n "$TEMPLATE" ] && [ -f "$TEMPLATE" ]; then
    cp "$TEMPLATE" "$SPEC_FILE"
else
    touch "$SPEC_FILE"
fi

# Set environment variables
export SPECIFY_FEATURE="$BRANCH_NAME"

# =============================================================================
# OUTPUT
# =============================================================================

if $JSON_MODE; then
    cat << EOF
{
  "BRANCH_NAME": "$BRANCH_NAME",
  "SPEC_FILE": "$SPEC_FILE",
  "FEATURE_NUM": "$FEATURE_NUM",
  "FEATURE_DIR": "$FEATURE_DIR",
  "PROJECT_NAME": "$PROJECT_NAME",
  "PROJECT_ROOT": "$PROJECT_ROOT",
  "WORKSPACE_MODE": $WORKSPACE_MODE,
  "SPECS_DIR": "$SPECS_DIR"
}
EOF
else
    echo ""
    echo "=============================================="
    echo "  FEATURE CREATED"
    echo "=============================================="
    echo ""
    if [ "$WORKSPACE_MODE" = true ]; then
        echo "  Project:     $PROJECT_NAME"
    fi
    echo "  Branch:      $BRANCH_NAME"
    echo "  Spec File:   $SPEC_FILE"
    echo "  Feature Dir: $FEATURE_DIR"
    echo ""
    echo "  NEXT STEPS:"
    echo "  ─────────────────────────────────────────"
    echo "  cd $PROJECT_ROOT"
    echo "  # Edit the spec, then run:"
    echo "  /speckit.plan"
    echo "  /speckit.tasks"
    echo "  /speckit.implement"
    echo ""
    echo "  SPECIFY_FEATURE=$BRANCH_NAME"
    echo "=============================================="
fi
