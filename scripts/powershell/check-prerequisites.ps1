#!/usr/bin/env pwsh

# Consolidated prerequisite checking script (PowerShell)
# Version: 2.0.0 - Multi-repository workspace support
#
# This script provides unified prerequisite checking for Spec-Driven Development workflow.
# It replaces the functionality previously spread across multiple scripts.
#
# Usage: ./check-prerequisites.ps1 [OPTIONS]
#
# OPTIONS:
#   -Json               Output in JSON format
#   -RequireTasks       Require tasks.md to exist (for implementation phase)
#   -IncludeTasks       Include tasks.md in AVAILABLE_DOCS list
#   -PathsOnly          Only output path variables (no validation)
#   -Feature <ref>      Specify feature by shorthand (e.g., myrepo-001)
#   -ListFeatures       List all features across workspace
#   -ListProjects       List all projects in workspace
#   -WorkspaceInfo      Output full workspace context as JSON (for AI agents)
#   -Help, -h           Show help message

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$RequireTasks,
    [switch]$IncludeTasks,
    [switch]$PathsOnly,
    [string]$Feature,
    [switch]$ListFeatures,
    [switch]$ListProjects,
    [switch]$WorkspaceInfo,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# Show help if requested
if ($Help) {
    Write-Output @"
Usage: check-prerequisites.ps1 [OPTIONS]

Consolidated prerequisite checking for Spec-Driven Development workflow.
Version 2.0.0 - Multi-repository workspace support

OPTIONS:
  -Json               Output in JSON format
  -RequireTasks       Require tasks.md to exist (for implementation phase)
  -IncludeTasks       Include tasks.md in AVAILABLE_DOCS list
  -PathsOnly          Only output path variables (no prerequisite validation)
  -Feature <ref>      Specify feature by shorthand (e.g., myrepo-001 or 001-desc)
  -ListFeatures       List all features across workspace
  -ListProjects       List all projects in workspace (workspace mode only)
  -WorkspaceInfo      Output full workspace context as JSON (for AI agents)
  -Help, -h           Show this help message

WORKSPACE MODE:
  When workspace.yaml is detected, the script operates in workspace mode:
  - Features use shorthand format: project-NNN (e.g., myrepo-001)
  - Specs are stored centrally in {workspace}/specs/{project}/{feature}/
  - Projects are auto-detected from subdirectories with .git or .specify

EXAMPLES:
  # Check task prerequisites (plan.md required)
  .\check-prerequisites.ps1 -Json
  
  # Check implementation prerequisites (plan.md + tasks.md required)
  .\check-prerequisites.ps1 -Json -RequireTasks -IncludeTasks
  
  # Get feature paths only (no validation)
  .\check-prerequisites.ps1 -PathsOnly
  
  # Work with specific feature (workspace mode)
  .\check-prerequisites.ps1 -Feature myrepo-001 -Json
  
  # List all features in workspace
  .\check-prerequisites.ps1 -ListFeatures
  
  # Get full workspace context for AI agents
  .\check-prerequisites.ps1 -WorkspaceInfo

"@
    exit 0
}

# Source common functions
. "$PSScriptRoot/common.ps1"

# Handle --list-projects
if ($ListProjects) {
    if (-not (Test-WorkspaceMode)) {
        if ($Json) {
            Write-Output '{"error":"Not in workspace mode","projects":[]}'
        } else {
            Write-Output "Not in workspace mode. Use 'specify workspace --here' to initialize."
        }
        exit 0
    }
    
    $projects = Get-Projects
    if ($Json) {
        Write-Output ($projects | ConvertTo-Json -Compress)
    } else {
        Write-Output "Projects in workspace:"
        foreach ($p in $projects) {
            Write-Output "  - $p"
        }
    }
    exit 0
}

# Handle --list-features
if ($ListFeatures) {
    $features = Get-WorkspaceFeatures
    if ($Json) {
        Write-Output ($features | ConvertTo-Json -Compress)
    } else {
        Write-Output "Features:"
        foreach ($f in $features) {
            Write-Output "  $($f.Shorthand): $($f.Path)"
        }
    }
    exit 0
}

# Handle --workspace-info (for AI agents)
if ($WorkspaceInfo) {
    $workspaceRoot = Get-WorkspaceRoot
    $isWorkspaceMode = Test-WorkspaceMode
    $projects = @()
    $features = @()
    
    if ($isWorkspaceMode) {
        $projects = Get-Projects
        $featuresRaw = Get-WorkspaceFeatures
        foreach ($f in $featuresRaw) {
            $features += $f.Shorthand
        }
    }
    
    $info = [PSCustomObject]@{
        workspace_mode = $isWorkspaceMode
        workspace_root = $workspaceRoot
        projects = $projects
        features = $features
    }
    Write-Output ($info | ConvertTo-Json -Compress)
    exit 0
}

# Handle --feature parameter
$project = $null
if ($Feature) {
    $parsed = Parse-FeatureShorthand -Ref $Feature
    if ($parsed.Valid) {
        if ($parsed.Project) {
            $env:SPECIFY_PROJECT = $parsed.Project
            $project = $parsed.Project
        }
        # Find the full feature name from specs
        $specsDir = Get-SpecsDir
        if ($parsed.Project) {
            $projectSpecsDir = Join-Path $specsDir $parsed.Project
            if (Test-Path $projectSpecsDir) {
                $featureDir = Get-ChildItem -Path $projectSpecsDir -Directory | Where-Object {
                    $_.Name -match "^$($parsed.Number)-"
                } | Select-Object -First 1
                if ($featureDir) {
                    $env:SPECIFY_FEATURE = $featureDir.Name
                }
            }
        } else {
            # Legacy format
            $featureDir = Get-ChildItem -Path $specsDir -Directory | Where-Object {
                $_.Name -match "^$($parsed.Number)-"
            } | Select-Object -First 1
            if ($featureDir) {
                $env:SPECIFY_FEATURE = $featureDir.Name
            }
        }
    } else {
        Write-Error "Invalid feature format: $Feature. Use project-NNN (e.g., myrepo-001) or NNN-description"
        exit 1
    }
}

# Get feature paths and validate branch
$paths = Get-FeaturePathsEnv -Project $project

if (-not (Test-FeatureBranch -Branch $paths.CURRENT_BRANCH -HasGit:$paths.HAS_GIT)) { 
    exit 1 
}

# If paths-only mode, output paths and exit (support combined -Json -PathsOnly)
if ($PathsOnly) {
    $output = [PSCustomObject]@{
        REPO_ROOT    = $paths.REPO_ROOT
        BRANCH       = $paths.CURRENT_BRANCH
        FEATURE_DIR  = $paths.FEATURE_DIR
        FEATURE_SPEC = $paths.FEATURE_SPEC
        IMPL_PLAN    = $paths.IMPL_PLAN
        TASKS        = $paths.TASKS
        WORKSPACE_MODE = $paths.WORKSPACE_MODE
    }
    if ($paths.PROJECT) {
        $output | Add-Member -NotePropertyName PROJECT -NotePropertyValue $paths.PROJECT
    }
    
    if ($Json) {
        Write-Output ($output | ConvertTo-Json -Compress)
    } else {
        Write-Output "REPO_ROOT: $($paths.REPO_ROOT)"
        Write-Output "BRANCH: $($paths.CURRENT_BRANCH)"
        Write-Output "FEATURE_DIR: $($paths.FEATURE_DIR)"
        Write-Output "FEATURE_SPEC: $($paths.FEATURE_SPEC)"
        Write-Output "IMPL_PLAN: $($paths.IMPL_PLAN)"
        Write-Output "TASKS: $($paths.TASKS)"
        Write-Output "WORKSPACE_MODE: $($paths.WORKSPACE_MODE)"
        if ($paths.PROJECT) {
            Write-Output "PROJECT: $($paths.PROJECT)"
        }
    }
    exit 0
}

# Validate required directories and files
if (-not (Test-Path $paths.FEATURE_DIR -PathType Container)) {
    Write-Output "ERROR: Feature directory not found: $($paths.FEATURE_DIR)"
    Write-Output "Run /speckit.specify first to create the feature structure."
    exit 1
}

if (-not (Test-Path $paths.IMPL_PLAN -PathType Leaf)) {
    Write-Output "ERROR: plan.md not found in $($paths.FEATURE_DIR)"
    Write-Output "Run /speckit.plan first to create the implementation plan."
    exit 1
}

# Check for tasks.md if required
if ($RequireTasks -and -not (Test-Path $paths.TASKS -PathType Leaf)) {
    Write-Output "ERROR: tasks.md not found in $($paths.FEATURE_DIR)"
    Write-Output "Run /speckit.tasks first to create the task list."
    exit 1
}

# Build list of available documents
$docs = @()

# Always check these optional docs
if (Test-Path $paths.RESEARCH) { $docs += 'research.md' }
if (Test-Path $paths.DATA_MODEL) { $docs += 'data-model.md' }

# Check contracts directory (only if it exists and has files)
if ((Test-Path $paths.CONTRACTS_DIR) -and (Get-ChildItem -Path $paths.CONTRACTS_DIR -ErrorAction SilentlyContinue | Select-Object -First 1)) { 
    $docs += 'contracts/' 
}

if (Test-Path $paths.QUICKSTART) { $docs += 'quickstart.md' }

# Include tasks.md if requested and it exists
if ($IncludeTasks -and (Test-Path $paths.TASKS)) { 
    $docs += 'tasks.md' 
}

# Output results
if ($Json) {
    # JSON output
    $output = [PSCustomObject]@{ 
        FEATURE_DIR = $paths.FEATURE_DIR
        AVAILABLE_DOCS = $docs
        WORKSPACE_MODE = $paths.WORKSPACE_MODE
    }
    if ($paths.PROJECT) {
        $output | Add-Member -NotePropertyName PROJECT -NotePropertyValue $paths.PROJECT
    }
    Write-Output ($output | ConvertTo-Json -Compress)
} else {
    # Text output
    Write-Output "FEATURE_DIR:$($paths.FEATURE_DIR)"
    if ($paths.PROJECT) {
        Write-Output "PROJECT:$($paths.PROJECT)"
    }
    Write-Output "WORKSPACE_MODE:$($paths.WORKSPACE_MODE)"
    Write-Output "AVAILABLE_DOCS:"
    
    # Show status of each potential document
    Test-FileExists -Path $paths.RESEARCH -Description 'research.md' | Out-Null
    Test-FileExists -Path $paths.DATA_MODEL -Description 'data-model.md' | Out-Null
    Test-DirHasFiles -Path $paths.CONTRACTS_DIR -Description 'contracts/' | Out-Null
    Test-FileExists -Path $paths.QUICKSTART -Description 'quickstart.md' | Out-Null
    
    if ($IncludeTasks) {
        Test-FileExists -Path $paths.TASKS -Description 'tasks.md' | Out-Null
    }
}
