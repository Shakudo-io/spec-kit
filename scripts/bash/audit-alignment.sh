#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

show_help() {
    cat << 'EOF'
Usage: audit-alignment.sh [OPTIONS]

Audit workspace for 1-1-1 alignment violations between branches, worktrees, and specs.

Options:
  --json           Output results as JSON
  --quiet          Only show issues (suppress OK and MERGED statuses)
  --project NAME   Audit only the specified project
  --no-fetch       Skip git fetch (faster, uses local refs only)
  --help           Show this help message

Status Codes:
  OK               Branch + worktree + spec all aligned
  MERGED           Feature was merged (branch deleted, spec retained)
  ORPHAN_SPEC      Spec exists but no branch found (not merged)
  MISSING_WT       Branch exists but no worktree created
  DISTRIBUTED      Spec in wrong location (needs migration to centralized)

Exit Codes:
  0                All specs aligned (or only OK/MERGED statuses)
  1                Alignment issues found
  2                Error (not in workspace, etc.)

Examples:
  # Full workspace audit
  audit-alignment.sh

  # Fast audit (skip git fetch)
  audit-alignment.sh --no-fetch

  # JSON output for programmatic use
  audit-alignment.sh --json

  # Only show problems
  audit-alignment.sh --quiet

  # Audit specific project
  audit-alignment.sh --project monorepo
EOF
}

OUTPUT_FORMAT="table"
QUIET_MODE=false
FILTER_PROJECT=""
export AUDIT_SKIP_FETCH=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        --quiet|-q)
            QUIET_MODE=true
            shift
            ;;
        --project|-p)
            FILTER_PROJECT="$2"
            shift 2
            ;;
        --no-fetch)
            export AUDIT_SKIP_FETCH=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help >&2
            exit 2
            ;;
    esac
done

if ! workspace_root=$(get_workspace_root 2>/dev/null); then
    echo "ERROR: Not in a workspace. Run from a directory containing .specify/workspace.yaml" >&2
    exit 2
fi

declare -a results=()
issues_found=0
total_specs=0
ok_count=0
merged_count=0
orphan_count=0
missing_wt_count=0
distributed_count=0

while IFS=$'\t' read -r project feature status details spec_path expected_spec_path; do
    [[ -z "$project" ]] && continue
    
    if [[ -n "$FILTER_PROJECT" && "$project" != "$FILTER_PROJECT" ]]; then
        continue
    fi
    
    ((total_specs++)) || true
    
    case "$status" in
        "$ALIGN_OK")
            ((ok_count++)) || true
            ;;
        "$ALIGN_MERGED")
            ((merged_count++)) || true
            ;;
        "$ALIGN_ORPHAN_SPEC")
            ((orphan_count++)) || true
            ((issues_found++)) || true
            ;;
        "$ALIGN_MISSING_WORKTREE")
            ((missing_wt_count++)) || true
            ((issues_found++)) || true
            ;;
        "$ALIGN_DISTRIBUTED")
            ((distributed_count++)) || true
            ((issues_found++)) || true
            ;;
    esac
    
    results+=("$project|$feature|$status|$details|$spec_path|$expected_spec_path")
done < <(run_workspace_audit)

output_table() {
    printf "\n%-20s %-30s %-15s %s\n" "PROJECT" "FEATURE" "STATUS" "DETAILS"
    printf "%-20s %-30s %-15s %s\n" "-------" "-------" "------" "-------"
    
    for result in "${results[@]}"; do
        IFS='|' read -r project feature status details spec_path expected_spec_path <<< "$result"
        
        if $QUIET_MODE && [[ "$status" == "$ALIGN_OK" || "$status" == "$ALIGN_MERGED" ]]; then
            continue
        fi
        
        local status_display="$status"
        case "$status" in
            "$ALIGN_OK")
                status_display="✓ OK"
                ;;
            "$ALIGN_MERGED")
                status_display="⊕ MERGED"
                ;;
            "$ALIGN_ORPHAN_SPEC")
                status_display="⚠ ORPHAN"
                ;;
            "$ALIGN_MISSING_WORKTREE")
                status_display="⚠ NO_WT"
                ;;
            "$ALIGN_DISTRIBUTED")
                status_display="⚠ DISTRIBUTED"
                ;;
        esac
        
        printf "%-20s %-30s %-15s %s\n" "$project" "$feature" "$status_display" "$details"
    done
    
    echo ""
    echo "Summary: $total_specs specs audited"
    echo "  ✓ OK:          $ok_count"
    echo "  ⊕ Merged:      $merged_count"
    echo "  ⚠ Orphan:      $orphan_count"
    echo "  ⚠ Missing WT:  $missing_wt_count"
    echo "  ⚠ Distributed: $distributed_count"
    
    if [[ $issues_found -gt 0 ]]; then
        echo ""
        echo "Run 'migrate-spec.sh' to fix DISTRIBUTED specs."
        echo "Run '/speckit.migrate' in your AI agent for guided fixes."
    fi
}

output_json() {
    local json_results=""
    local first=true
    
    for result in "${results[@]}"; do
        IFS='|' read -r project feature status details spec_path expected_spec_path <<< "$result"
        
        if $QUIET_MODE && [[ "$status" == "$ALIGN_OK" || "$status" == "$ALIGN_MERGED" ]]; then
            continue
        fi
        
        $first || json_results+=","
        first=false
        
        json_results+=$(printf '\n    {"project":"%s","feature":"%s","status":"%s","details":"%s","spec_path":"%s","expected_spec_path":"%s"}' \
            "$project" "$feature" "$status" "$details" "$spec_path" "$expected_spec_path")
    done
    
    cat << EOF
{
  "workspace_root": "$workspace_root",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "summary": {
    "total": $total_specs,
    "ok": $ok_count,
    "merged": $merged_count,
    "orphan": $orphan_count,
    "missing_worktree": $missing_wt_count,
    "distributed": $distributed_count,
    "issues_found": $issues_found
  },
  "results": [$json_results
  ]
}
EOF
}

case "$OUTPUT_FORMAT" in
    json)
        output_json
        ;;
    *)
        output_table
        ;;
esac

if [[ $issues_found -gt 0 ]]; then
    exit 1
fi
exit 0
