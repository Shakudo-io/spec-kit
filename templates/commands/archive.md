---
description: Archive or unarchive a project in the workspace to hide it from discovery and listings.
---

## User Input

```text
$ARGUMENTS
```

## Overview

This command manages the `archived_projects` list in `workspace.yaml`. Archived projects remain on disk but are excluded from:
- `/speckit.workspace` project listings
- `/speckit.projects` output
- `/speckit.rollup` spec indexing
- `/speckit.specs` listings

## Argument Parsing

Parse `$ARGUMENTS` to determine the action and target:

| Pattern | Action | Example |
|---------|--------|---------|
| `<project>` | Archive the project | `/speckit.archive backend-api` |
| `--unarchive <project>` | Unarchive the project | `/speckit.archive --unarchive backend-api` |
| `--list` | List archived projects | `/speckit.archive --list` |
| (empty) | Show help/usage | `/speckit.archive` |

## Execution

### 1. Validate Workspace Mode

Check if in workspace mode by looking for `workspace.yaml`:
- Look for `.specify/workspace.yaml` or `workspace.yaml` in current or parent directories
- If not found, display error and suggest running `specify workspace --here`

### 2. Locate workspace.yaml

Find the workspace configuration file at one of:
- `{workspace}/.specify/workspace.yaml`
- `{workspace}/workspace.yaml`

### 3. Handle --list Action

If `--list` was specified:
1. Read the `archived_projects` list from workspace.yaml
2. Display the list:

```
## Archived Projects

| Project | Status |
|---------|--------|
| old-backend | archived |
| deprecated-service | archived |

Total: 2 archived project(s)
```

If no projects are archived, display: "No projects are currently archived."

### 4. Handle Archive Action

If archiving a project:

1. **Validate project exists**: Run `list_projects --include-archived` and verify the project name is valid
2. **Check not already archived**: If already in `archived_projects`, inform user and exit
3. **Update workspace.yaml**: Add the project to the `archived_projects` list

**Modification approach**:
- Read current workspace.yaml content
- If `archived_projects: []` exists, replace with multi-line format
- If `archived_projects:` with items exists, append new item
- If `archived_projects` key doesn't exist, add it before the `# PROJECT DISCOVERY` section

**Example transformation**:

Before:
```yaml
archived_projects: []
```

After:
```yaml
archived_projects:
  - backend-api
```

4. **Confirm success**:
```
Archived project: backend-api

The project will no longer appear in:
- /speckit.workspace listings
- /speckit.projects output  
- /speckit.rollup indexing
- /speckit.specs listings

To unarchive: /speckit.archive --unarchive backend-api
```

### 5. Handle Unarchive Action

If unarchiving a project:

1. **Validate project is archived**: Check if project is in `archived_projects` list
2. **Update workspace.yaml**: Remove the project from `archived_projects`
3. **Clean up empty list**: If list becomes empty, convert back to `archived_projects: []`

4. **Confirm success**:
```
Unarchived project: backend-api

The project is now visible in workspace listings and will be included in rollups.
```

## Error Handling

| Error | Message |
|-------|---------|
| Not in workspace | "ERROR: Not in a workspace. Initialize with: specify workspace --here" |
| Project not found | "ERROR: Project 'xyz' not found in workspace. Run /speckit.projects to see available projects." |
| Already archived | "Project 'xyz' is already archived." |
| Not archived | "Project 'xyz' is not archived." |
| workspace.yaml not writable | "ERROR: Cannot write to workspace.yaml. Check file permissions." |

## Examples

```bash
# Archive a project
/speckit.archive old-backend-api

# Unarchive a project
/speckit.archive --unarchive old-backend-api

# List all archived projects
/speckit.archive --list

# Show usage
/speckit.archive
```

## Notes

- Archiving is non-destructive: the project directory and all its contents remain on disk
- Archived projects can still be accessed directly via filesystem
- The `archived_projects` list is stored in workspace.yaml for version control visibility
- Use `/speckit.projects --include-archived` (if supported) to see all projects including archived ones
