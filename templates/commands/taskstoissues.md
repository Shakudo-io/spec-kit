---
description: Convert existing tasks into actionable, dependency-ordered GitHub issues for the feature based on available design artifacts.
tools: ['github/github-mcp-server/issue_write']
scripts:
  sh: scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks
  ps: scripts/powershell/check-prerequisites.ps1 -Json -RequireTasks -IncludeTasks
---

## Workspace Mode Support

In multi-repository workspaces, you can specify features using two formats:

- **Legacy shorthand**: `/speckit.taskstoissues monorepo-001` - converts tasks to issues for feature 001 in the monorepo project
- **Workspace spec ID**: `/speckit.taskstoissues monorepo:001-user-auth` - uses the rollup index to resolve the full path
- **From project directory**: If you're inside a project's git repo, the project is auto-detected
- **List all specs**: Run `/speckit.specs` or `scripts/bash/check-prerequisites.sh --list-specs` to see available specs

The `project:feature` format uses the workspace specs index (`.specify/specs-index.json`) for resolution. Run `/speckit.rollup` first to generate the index.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

1. Run `{SCRIPT}` from repo root and parse the JSON payload fields:
   
   **JSON fields (workspace mode with feature shorthand)**:
   - `SPEC_DIR`: Where spec documents live (spec.md, plan.md, tasks.md, etc.)
   - `SOURCE_DIR`: Where source code lives (for writing code changes)
   - `SOURCE_BRANCH`: Current branch of SOURCE_DIR
   - `IS_WORKTREE`: Whether SOURCE_DIR is a git worktree
   - `CONSTITUTION_PATH`: Absolute path to constitution.md
   - `AVAILABLE_DOCS`: List of existing spec documents
   
   **Legacy mode** (single-repo without workspace.yaml): Uses `FEATURE_DIR` instead of `SPEC_DIR`.
   
   - All paths must be absolute. 
   - For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").
1. From the executed script, extract the path to **tasks**.
1. Get the Git remote by running:

```bash
git config --get remote.origin.url
```

> [!CAUTION]
> ONLY PROCEED TO NEXT STEPS IF THE REMOTE IS A GITHUB URL

1. For each task in the list, use the GitHub MCP server to create a new issue in the repository that is representative of the Git remote.

> [!CAUTION]
> UNDER NO CIRCUMSTANCES EVER CREATE ISSUES IN REPOSITORIES THAT DO NOT MATCH THE REMOTE URL
