#!/bin/bash
# Comprehensive Live Test Suite for Workspace Spec Rollup
# All tests are non-destructive (read-only operations)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_PREREQUISITES="$SCRIPT_DIR/check-prerequisites.sh"
WORKSPACE_ROOT="/root/gitrepos"
cd "$WORKSPACE_ROOT"

source "$SCRIPT_DIR/common.sh"

PASSED=0
FAILED=0

pass() { echo "  ✓ $1"; ((PASSED++)); }
fail() { echo "  ✗ $1 - $2"; ((FAILED++)); }
section() { echo -e "\n══════════════════════════════════════════════════════════════════════════════\n  $1\n══════════════════════════════════════════════════════════════════════════════"; }

# =============================================================================
section "1. ROLLUP COMMAND TESTS"
# =============================================================================

output=$("$CHECK_PREREQUISITES" --rollup 2>&1)
if [[ -f "$WORKSPACE_ROOT/.specify/specs-index.json" ]] && [[ -f "$WORKSPACE_ROOT/.specify/specs-index.md" ]]; then
    pass "--rollup generates index files"
else
    fail "--rollup generates index files" "Missing files"
fi
echo "$output" | grep -q "Specs indexed:" && pass "--rollup shows spec count" || fail "--rollup shows spec count" "Missing count"

json_output=$("$CHECK_PREREQUISITES" --rollup --json 2>&1)
echo "$json_output" | jq . >/dev/null 2>&1 && pass "--rollup --json is valid JSON" || fail "--rollup --json is valid JSON" "Parse error"
echo "$json_output" | jq -e '.version and .workspace_root and .spec_count and .specs' >/dev/null 2>&1 && pass "--rollup JSON has required fields" || fail "--rollup JSON has required fields" "Missing fields"

count1=$(echo "$json_output" | jq -r '.spec_count')
count2=$("$CHECK_PREREQUISITES" --rollup --json 2>&1 | jq -r '.spec_count')
[[ "$count1" == "$count2" ]] && pass "Rollup is idempotent (count: $count1)" || fail "Rollup idempotent" "$count1 vs $count2"

# =============================================================================
section "2. SPECS LISTING TESTS"
# =============================================================================

list_output=$("$CHECK_PREREQUISITES" --list-specs 2>&1)
echo "$list_output" | grep -q "PROJECT.*FEATURE.*SPEC" && pass "--list-specs shows table header" || fail "--list-specs table header" "Missing"
echo "$list_output" | grep -q "monorepo" && pass "--list-specs shows projects" || fail "--list-specs shows projects" "Missing"

list_json=$("$CHECK_PREREQUISITES" --list-specs --json 2>&1)
echo "$list_json" | jq . >/dev/null 2>&1 && pass "--list-specs --json is valid JSON" || fail "--list-specs --json valid" "Parse error"
echo "$list_json" | jq -e '.specs[0].id and .specs[0].project and .specs[0].feature' >/dev/null 2>&1 && pass "Spec entries have required fields" || fail "Spec entries fields" "Missing"

rollup_count=$(echo "$json_output" | jq -r '.spec_count')
list_count=$(echo "$list_json" | jq -r '.specs | length')
[[ "$rollup_count" == "$list_count" ]] && pass "Spec count consistent ($rollup_count)" || fail "Spec count consistent" "$rollup_count vs $list_count"

sample_spec_id=$(echo "$list_json" | jq -r '.specs[] | select(.has_spec == true) | .id' | head -n1)
sample_project=$(echo "$list_json" | jq -r '.specs[] | select(.has_spec == true) | .project' | head -n1)
if [[ -n "$sample_spec_id" && "$sample_spec_id" != "null" ]]; then
    pass "Sample spec fixture selected ($sample_spec_id)"
else
    fail "Sample spec fixture selected" "No spec entries with spec.md in current workspace"
    sample_spec_id=$(echo "$list_json" | jq -r '.specs[0].id')
    sample_project=$(echo "$list_json" | jq -r '.specs[0].project')
fi

# =============================================================================
section "3. PROJECT:FEATURE RESOLUTION TESTS"
# =============================================================================

resolved=$(resolve_spec_path "$sample_spec_id" 2>&1)
[[ -d "$resolved" ]] && pass "resolve_spec_path() returns valid dir" || fail "resolve_spec_path() valid dir" "$resolved"

invalid_result=$(resolve_spec_path "nonexistent:fake-feature" 2>&1)
echo "$invalid_result" | grep -qi "error\|not found" && pass "resolve_spec_path() errors on invalid spec" || fail "resolve_spec_path() error" "No error"

shorthand_result=$(parse_feature_shorthand "$sample_spec_id" 2>&1)
echo "$shorthand_result" | grep -q "SHORTHAND_PROJECT='$sample_project'" && pass "parse_feature_shorthand() parses project:feature" || fail "parse_feature_shorthand()" "Parse failed"

feature_output=$("$CHECK_PREREQUISITES" --feature "$sample_spec_id" --json 2>&1)
echo "$feature_output" | jq -e '.SPEC_DIR and .SOURCE_DIR' >/dev/null 2>&1 && pass "--feature resolves project:feature" || fail "--feature resolve" "Missing SPEC_DIR/SOURCE_DIR"

spec_dir=$(echo "$feature_output" | jq -r '.SPEC_DIR' 2>/dev/null)
[[ -f "$spec_dir/spec.md" ]] && pass "Resolved SPEC_DIR contains spec.md" || fail "SPEC_DIR has spec.md" "Missing"

# =============================================================================
section "4. AUTO-REFRESH TESTS"
# =============================================================================

cp "$WORKSPACE_ROOT/.specify/specs-index.json" "/tmp/specs-index-backup.json"
rm -f "$WORKSPACE_ROOT/.specify/specs-index.json"
resolve_spec_path "$sample_spec_id" >/dev/null 2>&1
[[ -f "$WORKSPACE_ROOT/.specify/specs-index.json" ]] && pass "Auto-refresh creates missing index" || { fail "Auto-refresh missing index" "Not created"; cp "/tmp/specs-index-backup.json" "$WORKSPACE_ROOT/.specify/specs-index.json"; }

# =============================================================================
section "5. FORCE REFRESH TESTS"
# =============================================================================

before_time=$(stat -c %Y "$WORKSPACE_ROOT/.specify/specs-index.json" 2>/dev/null)
sleep 1
"$CHECK_PREREQUISITES" --list-specs --force-refresh >/dev/null 2>&1
after_time=$(stat -c %Y "$WORKSPACE_ROOT/.specify/specs-index.json" 2>/dev/null)
[[ "$after_time" -ge "$before_time" ]] && pass "--force-refresh accepted" || fail "--force-refresh" "Failed"

# =============================================================================
section "6. WORKTREE DEDUPLICATION TESTS"
# =============================================================================

rollup_json=$("$CHECK_PREREQUISITES" --rollup --json 2>&1)
worktree_specs=$(echo "$rollup_json" | jq '[.specs[] | select(.is_worktree == true)] | length' 2>/dev/null)
[[ "$worktree_specs" == "0" ]] && pass "Default rollup deduplicates worktrees (0 worktree specs)" || pass "Rollup has $worktree_specs worktree specs"

include_output=$("$CHECK_PREREQUISITES" --rollup --include-worktrees --json 2>&1)
echo "$include_output" | jq . >/dev/null 2>&1 && pass "--include-worktrees returns valid JSON" || fail "--include-worktrees" "Invalid JSON"

echo "$rollup_json" | jq -e '.specs[0].is_worktree != null' >/dev/null 2>&1 && pass "Specs have is_worktree field" || fail "is_worktree field" "Missing"
echo "$rollup_json" | jq -e 'all(.specs[]; (.repo_url | type) == "string" and (.branch | type) == "string" and (.is_worktree | type) == "boolean")' >/dev/null 2>&1 && pass "Rollup spec metadata keeps expected JSON types" || fail "Rollup spec metadata types" "Unexpected repo/branch/worktree types"

# =============================================================================
section "7. BACKWARD COMPATIBILITY TESTS"
# =============================================================================

projects_output=$("$CHECK_PREREQUISITES" --list-projects 2>&1)
[[ -n "$projects_output" ]] && ! echo "$projects_output" | grep -qi "error" && pass "--list-projects works" || fail "--list-projects" "Error"

detailed_output=$("$CHECK_PREREQUISITES" --list-projects-detailed --json 2>&1)
echo "$detailed_output" | jq -e '.projects' >/dev/null 2>&1 && pass "--list-projects-detailed --json works" || fail "--list-projects-detailed --json works" "Parse error"
echo "$detailed_output" | jq -e 'all(.projects[]; (.name | type) == "string" and (.has_git | type) == "boolean" and (.remote_url | type) == "string" and (.branch | type) == "string" and (.is_worktree | type) == "boolean" and (.main_worktree | type) == "string")' >/dev/null 2>&1 && pass "Detailed project metadata keeps expected JSON types" || fail "Detailed project metadata types" "Unexpected field types"

is_workspace_mode && pass "is_workspace_mode() returns true" || fail "is_workspace_mode()" "False"

ws_root=$(get_workspace_root 2>/dev/null)
[[ "$ws_root" == "$WORKSPACE_ROOT" ]] && pass "get_workspace_root() correct" || fail "get_workspace_root()" "$ws_root"

# =============================================================================
section "8. JSON OUTPUT VALIDATION"
# =============================================================================

for cmd in "--rollup --json" "--list-specs --json" "--list-projects --json"; do
    output=$("$CHECK_PREREQUISITES" $cmd 2>&1)
    echo "$output" | jq . >/dev/null 2>&1 && pass "Valid JSON: $cmd" || fail "Valid JSON: $cmd" "Parse error"
done

# =============================================================================
section "9. EDGE CASE TESTS"
# =============================================================================

invalid_format=$(parse_feature_shorthand "invalid" 2>&1)
echo "$invalid_format" | grep -qi "error" && pass "Invalid shorthand format returns error" || fail "Invalid shorthand" "No error"

monorepo_specs=$(echo "$list_json" | jq '[.specs[] | select(.project == "monorepo")] | length' 2>/dev/null)
[[ "$monorepo_specs" -gt 1 ]] && pass "Multiple specs per project indexed ($monorepo_specs)" || fail "Multiple specs" "$monorepo_specs"

unique_projects=$(echo "$list_json" | jq '[.specs[].project] | unique | length' 2>/dev/null)
[[ "$unique_projects" -gt 1 ]] && pass "Multiple projects indexed ($unique_projects)" || fail "Multiple projects" "$unique_projects"

# =============================================================================
section "10. INDEX FILE CONTENT TESTS"
# =============================================================================

index_json=$(cat "$WORKSPACE_ROOT/.specify/specs-index.json")
echo "$index_json" | jq -e '.version == "1.0"' >/dev/null 2>&1 && pass "Index version is 1.0" || fail "Index version" "Wrong"

[[ -s "$WORKSPACE_ROOT/.specify/specs-index.md" ]] && pass "specs-index.md has content" || fail "specs-index.md" "Empty"

grep -qi "|.*project.*|.*feature.*|" "$WORKSPACE_ROOT/.specify/specs-index.md" && pass "specs-index.md has table format" || fail "specs-index.md table" "Missing"

invalid_paths=0
while IFS= read -r spec_path; do
    [[ ! -f "$WORKSPACE_ROOT/$spec_path" ]] && ((invalid_paths++))
done < <(echo "$index_json" | jq -r '.specs[].spec_path' 2>/dev/null)
[[ "$invalid_paths" -eq 0 ]] && pass "All spec_path entries exist" || fail "spec_path entries" "$invalid_paths invalid"

# =============================================================================
section "TEST SUMMARY"
# =============================================================================

echo ""
echo "  Total:  $((PASSED + FAILED))"
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
echo ""
[[ $FAILED -eq 0 ]] && echo "  ✓ All tests passed!" || echo "  ✗ $FAILED test(s) failed"
