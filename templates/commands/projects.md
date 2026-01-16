---
description: List all valid projects in the workspace with their repository and branch information.
scripts:
  sh: scripts/bash/check-prerequisites.sh --list-projects-detailed --json
  ps: scripts/powershell/check-prerequisites.ps1 -ListProjectsDetailed -Json
---

## User Input

```text
$ARGUMENTS
```

## Outline

1. **Run the script**: Execute `{SCRIPT}` from the workspace root to get project information.

2. **Parse the JSON output**: The script returns a JSON object with:
   - `workspace_root`: The absolute path to the workspace
   - `projects`: An array of project objects, each containing:
     - `name`: The project directory name
     - `has_git`: Whether the project is a git repository (true/false)
     - `remote_url`: The git remote origin URL (empty if not a git repo)
     - `branch`: The current git branch (empty if not a git repo)

3. **Display the results**: Format and display the project information in a clear table:

   ```
   ## Workspace Projects
   
   **Workspace Root**: /path/to/workspace
   
   | Project | Git | Branch | Remote URL |
   |---------|-----|--------|------------|
   | backend-api | Yes | main | git@github.com:org/backend-api.git |
   | frontend | Yes | develop | git@github.com:org/frontend.git |
   | shared-lib | No | - | - |
   ```

4. **Handle edge cases**:
   - If not in workspace mode, inform the user to initialize with `specify workspace --here`
   - If no projects found, suggest adding git repositories to the workspace directory

## Notes

- Projects are auto-detected as directories containing `.git` or `.specify` folders
- The remote URL shown is the `origin` remote
- Use `/speckit.workspace` for a broader workspace status including features
