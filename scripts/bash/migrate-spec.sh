#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

show_help() {
    cat << 'EOF'
Usage: migrate-spec.sh [OPTIONS] [PROJECT:FEATURE...]

Migrate specs to fix 1-1-1 alignment issues.

Options:
  --dry-run        Show what would be done without making changes (default)
  --execute        Actually perform the migrations
  --all            Migrate all distributed specs
  --create-wt      Also create missing worktrees
  --base-branch B  Branch to use as base for new branches (default: main)
  --rollup         Run specs rollup after migration
  --help           Show this help message

Arguments:
  PROJECT:FEATURE  Specific specs to migrate (e.g., monorepo:001-user-auth)
                   If not provided, use --all to migrate everything

Migration Actions:
  DISTRIBUTED    → Move spec from repo to centralized location
  MISSING_WT     → Create worktree for existing branch (with --create-wt)
  ORPHAN_SPEC    → No automatic fix; requires manual decision

Examples:
  # Preview all migrations
  migrate-spec.sh --all

  # Migrate a specific spec
  migrate-spec.sh --execute monorepo:001-user-auth

  # Migrate all and create worktrees
  migrate-spec.sh --execute --all --create-wt

  # Migrate with rollup
  migrate-spec.sh --execute --all --rollup
EOF
}

DRY_RUN=true
MIGRATE_ALL=false
CREATE_WORKTREES=false
BASE_BRANCH="main"
DO_ROLLUP=false
SPECS_TO_MIGRATE=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --execute)
            DRY_RUN=false
            shift
            ;;
        --all)
            MIGRATE_ALL=true
            shift
            ;;
        --create-wt|--create-worktree)
            CREATE_WORKTREES=true
            shift
            ;;
        --base-branch|-b)
            BASE_BRANCH="$2"
            shift 2
            ;;
        --rollup)
            DO_ROLLUP=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            show_help >&2
            exit 2
            ;;
        *)
            SPECS_TO_MIGRATE+=("$1")
            shift
            ;;
    esac
done

if ! workspace_root=$(get_workspace_root 2>/dev/null); then
    echo "ERROR: Not in a workspace. Run from a directory containing .specify/workspace.yaml" >&2
    exit 2
fi

if ! $MIGRATE_ALL && [[ ${#SPECS_TO_MIGRATE[@]} -eq 0 ]]; then
    echo "ERROR: Specify specs to migrate or use --all" >&2
    show_help >&2
    exit 2
fi

declare -A audit_results
migrate_count=0
worktree_count=0
error_count=0

echo "Auditing workspace alignment..."
while IFS=$'\t' read -r project feature status details spec_path expected_spec_path; do
    [[ -z "$project" ]] && continue
    
    spec_id="${project}:${feature}"
    audit_results["$spec_id"]="$status|$details|$spec_path|$expected_spec_path"
done < <(run_workspace_audit)

should_migrate() {
    local spec_id="$1"
    
    if $MIGRATE_ALL; then
        return 0
    fi
    
    for target in "${SPECS_TO_MIGRATE[@]}"; do
        if [[ "$target" == "$spec_id" ]]; then
            return 0
        fi
        local target_project="${target%%:*}"
        local target_feature="${target#*:}"
        local spec_project="${spec_id%%:*}"
        local spec_feature="${spec_id#*:}"
        if [[ "$target_project" == "$spec_project" && "$spec_feature" == "$target_feature"* ]]; then
            return 0
        fi
    done
    
    return 1
}

echo ""
if $DRY_RUN; then
    echo "=== DRY RUN MODE (use --execute to apply) ==="
else
    echo "=== EXECUTING MIGRATIONS ==="
fi
echo ""

for spec_id in "${!audit_results[@]}"; do
    IFS='|' read -r status details spec_path expected_spec_path <<< "${audit_results[$spec_id]}"
    
    project="${spec_id%%:*}"
    feature="${spec_id#*:}"
    
    if ! should_migrate "$spec_id"; then
        continue
    fi
    
    case "$status" in
        "$ALIGN_DISTRIBUTED")
            echo "[$spec_id] DISTRIBUTED → CENTRALIZED"
            echo "  From: $spec_path"
            echo "  To:   $expected_spec_path"
            
            if $DRY_RUN; then
                echo "  [DRY-RUN] Would move spec directory"
            else
                if migrate_spec_to_centralized "$project" "$feature" "$spec_path" "false"; then
                    echo "  ✓ Migrated successfully"
                    ((migrate_count++))
                else
                    echo "  ✗ Migration failed"
                    ((error_count++))
                fi
            fi
            echo ""
            ;;
            
        "$ALIGN_MISSING_WORKTREE")
            if $CREATE_WORKTREES; then
                echo "[$spec_id] CREATE WORKTREE"
                echo "  Branch: ${project}-${feature}"
                
                if $DRY_RUN; then
                    echo "  [DRY-RUN] Would create worktree"
                else
                    if create_feature_worktree "$project" "$feature" "$BASE_BRANCH"; then
                        echo "  ✓ Worktree created"
                        ((worktree_count++))
                    else
                        echo "  ✗ Failed to create worktree"
                        ((error_count++))
                    fi
                fi
                echo ""
            else
                echo "[$spec_id] MISSING_WT (use --create-wt to fix)"
            fi
            ;;
            
        "$ALIGN_ORPHAN_SPEC")
            echo "[$spec_id] ORPHAN (manual review needed)"
            echo "  $details"
            echo "  Options: create branch+worktree, or archive the spec"
            echo ""
            ;;
            
        "$ALIGN_OK"|"$ALIGN_MERGED")
            ;;
    esac
done

echo ""
echo "=== SUMMARY ==="
if $DRY_RUN; then
    echo "DRY RUN - no changes made"
fi
echo "Specs migrated:    $migrate_count"
echo "Worktrees created: $worktree_count"
echo "Errors:            $error_count"

if $DO_ROLLUP && ! $DRY_RUN && [[ $migrate_count -gt 0 || $worktree_count -gt 0 ]]; then
    echo ""
    echo "Running specs rollup..."
    if generate_specs_index >/dev/null; then
        echo "✓ Specs index updated"
    else
        echo "✗ Failed to update specs index"
        ((error_count++))
    fi
fi

if [[ $error_count -gt 0 ]]; then
    exit 1
fi
exit 0
