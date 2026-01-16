#!/usr/bin/env pwsh

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$FeatureArg,
    [switch]$Json,
    [string]$Feature,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Output "Usage: ./setup-plan.ps1 [-Json] [-Feature <ref>] [feature-shorthand] [-Help]"
    Write-Output ""
    Write-Output "OPTIONS:"
    Write-Output "  -Json              Output results in JSON format"
    Write-Output "  -Feature <ref>     Feature shorthand (e.g., monorepo-001)"
    Write-Output "  feature-shorthand  Positional argument for feature shorthand"
    Write-Output "  -Help              Show this help message"
    Write-Output ""
    Write-Output "EXAMPLES:"
    Write-Output "  ./setup-plan.ps1 -Json monorepo-001"
    Write-Output "  ./setup-plan.ps1 -Json -Feature backend-api-002"
    exit 0
}

. "$PSScriptRoot/common.ps1"

$featureRef = if ($Feature) { $Feature } elseif ($FeatureArg) { $FeatureArg } else { $null }
$project = $null

if ($featureRef) {
    if (-not (Test-WorkspaceMode)) {
        Write-Error "Feature shorthand ($featureRef) only works in workspace mode"
        exit 1
    }
    
    $parsed = Parse-FeatureShorthand -Ref $featureRef
    if ($parsed.Valid -and $parsed.Project) {
        $validProjects = Get-Projects
        if (-not ($validProjects -contains $parsed.Project)) {
            Write-Output "ERROR: Invalid project '$($parsed.Project)' in shorthand '$featureRef'"
            Write-Output ""
            Write-Output "Available projects:"
            foreach ($p in $validProjects) {
                Write-Output "  - $p"
            }
            exit 1
        }
        
        $env:SPECIFY_PROJECT = $parsed.Project
        $project = $parsed.Project
        
        $specsDir = Get-SpecsDir
        $projectSpecsDir = Join-Path $specsDir $parsed.Project
        if (Test-Path $projectSpecsDir) {
            $featureDir = Get-ChildItem -Path $projectSpecsDir -Directory | Where-Object {
                $_.Name -match "^$($parsed.Number)-"
            } | Select-Object -First 1
            if ($featureDir) {
                $env:SPECIFY_FEATURE = $featureDir.Name
            }
        }
    } elseif (-not $parsed.Valid) {
        Write-Error "Invalid feature format: $featureRef. Use project-NNN (e.g., myrepo-001)"
        exit 1
    }
}

$paths = Get-FeaturePathsEnv -Project $project

# Check if we're on a proper feature branch (only for git repos)
if (-not (Test-FeatureBranch -Branch $paths.CURRENT_BRANCH -HasGit $paths.HAS_GIT)) { 
    exit 1 
}

# Ensure the feature directory exists
New-Item -ItemType Directory -Path $paths.FEATURE_DIR -Force | Out-Null

# Copy plan template if it exists, otherwise note it or create empty file
$template = Join-Path $paths.REPO_ROOT '.specify/templates/plan-template.md'
if (Test-Path $template) { 
    Copy-Item $template $paths.IMPL_PLAN -Force
    Write-Output "Copied plan template to $($paths.IMPL_PLAN)"
} else {
    Write-Warning "Plan template not found at $template"
    # Create a basic plan file if template doesn't exist
    New-Item -ItemType File -Path $paths.IMPL_PLAN -Force | Out-Null
}

# Output results
if ($Json) {
    $result = [PSCustomObject]@{ 
        FEATURE_SPEC = $paths.FEATURE_SPEC
        IMPL_PLAN = $paths.IMPL_PLAN
        SPECS_DIR = $paths.FEATURE_DIR
        BRANCH = $paths.CURRENT_BRANCH
        HAS_GIT = $paths.HAS_GIT
    }
    $result | ConvertTo-Json -Compress
} else {
    Write-Output "FEATURE_SPEC: $($paths.FEATURE_SPEC)"
    Write-Output "IMPL_PLAN: $($paths.IMPL_PLAN)"
    Write-Output "SPECS_DIR: $($paths.FEATURE_DIR)"
    Write-Output "BRANCH: $($paths.CURRENT_BRANCH)"
    Write-Output "HAS_GIT: $($paths.HAS_GIT)"
}
