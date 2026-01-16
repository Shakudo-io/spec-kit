---
description: Show workspace status, list projects and features, and display AI discovery information.
scripts:
  sh: scripts/bash/check-prerequisites.sh --workspace-info
  ps: scripts/powershell/check-prerequisites.ps1 -WorkspaceInfo
---

## User Input

```text
$ARGUMENTS
```

## Overview

This command provides workspace status and discovery information for multi-repository Spec-Kit setups. It helps AI agents and users understand the current workspace context.

## Execution

1. **Check Workspace Mode**: Determine if we're in a workspace (has `workspace.yaml`) or legacy single-repo mode.

2. **Gather Workspace Information** by running the appropriate script:

   **Bash:**
   ```bash
   {SCRIPT}
   ```

   **PowerShell:**
   ```powershell
   {SCRIPT}
   ```

3. **Parse and Display Results**: The script returns JSON with:
   - `workspace_mode`: Boolean indicating if workspace mode is active
   - `workspace_root`: Path to workspace root directory
   - `projects`: Array of detected project names
   - `features`: Array of feature shorthands (e.g., `myrepo-001`)

4. **Handle User Arguments**: If the user provided arguments (in `$ARGUMENTS`), interpret them:

   | Argument | Action |
   |----------|--------|
   | `--list-projects` or `projects` | List all projects with their paths |
   | `--list-features` or `features` | List all features with their shorthands |
   | `--info` or empty | Show full workspace context |
   | `<project-name>` | Show features for specific project |
   | `<feature-shorthand>` | Show details for specific feature |

5. **Display Status** based on workspace mode:

   **If in workspace mode:**
   ```markdown
   ## Workspace: {workspace_name}
   
   **Path**: {workspace_root}
   **Mode**: Multi-repository workspace
   
   ### Projects ({count})
   | Project | Status | Features |
   |---------|--------|----------|
   | {project} | {has_git ? "Git" : "No Git"} | {feature_count} |
   
   ### Features ({count})
   | Shorthand | Project | Branch | Status |
   |-----------|---------|--------|--------|
   | {shorthand} | {project} | {branch_name} | {exists ? "Active" : "Pending"} |
   
   ### Quick Commands
   - Create feature: `/speckit.specify --project <name> <description>`
   - Work on feature: `/speckit.plan <shorthand>`, `/speckit.tasks <shorthand>`
   - List projects: `.specify/scripts/bash/check-prerequisites.sh --list-projects`
   ```

   **If in legacy mode:**
   ```markdown
   ## Single Repository Mode
   
   **Path**: {repo_root}
   **Branch**: {current_branch}
   
   This repository is not configured as a workspace. Features are stored in `specs/`.
   
   ### To Enable Workspace Mode
   Run `specify workspace --here` from the parent directory containing multiple repos.
   ```

6. **Provide Context for AI Agents**:
   
   If asked for AI-consumable context, output a structured summary:
   ```json
   {
     "workspace_mode": true,
     "workspace_root": "/path/to/workspace",
     "projects": ["repo-a", "repo-b", "repo-c"],
     "features": [
       {"shorthand": "repo-a-001", "project": "repo-a", "name": "001-feature-name"},
       {"shorthand": "repo-b-001", "project": "repo-b", "name": "001-other-feature"}
     ],
     "current_project": null,
     "current_feature": null
   }
   ```

## Error Handling

- **Not in workspace**: Display legacy mode information and instructions to enable workspace
- **Empty workspace**: Suggest adding project directories or running `git clone`
- **No features**: Explain how to create features with `/speckit.specify --project`

## Examples

```bash
# Show workspace status
/speckit.workspace

# List all projects
/speckit.workspace projects

# List all features
/speckit.workspace features

# Show features for specific project
/speckit.workspace myrepo

# Show details for specific feature
/speckit.workspace myrepo-001
```
