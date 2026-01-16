#!/usr/bin/env pwsh
# Common PowerShell functions analogous to common.sh
# Version: 2.0.0 - Multi-repository workspace support

# =============================================================================
# WORKSPACE DETECTION
# =============================================================================

function Get-WorkspaceRoot {
    # Check explicit env var first
    if ($env:SPECIFY_WORKSPACE) {
        return $env:SPECIFY_WORKSPACE
    }
    
    # Look for workspace.yaml upward from current dir
    $dir = Get-Location
    while ($dir) {
        # Check for spec-kit structure: scripts/powershell/workspace.yaml
        if (Test-Path (Join-Path $dir "scripts/powershell/workspace.yaml")) {
            return $dir.Path
        }
        # Check for installed structure: .specify/workspace.yaml
        if (Test-Path (Join-Path $dir ".specify/workspace.yaml")) {
            return $dir.Path
        }
        # Check for workspace.yaml at root
        if (Test-Path (Join-Path $dir "workspace.yaml")) {
            return $dir.Path
        }
        
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) {
            break
        }
        $dir = $parent
    }
    
    # No workspace found - return empty (legacy mode)
    return $null
}

function Test-WorkspaceMode {
    return $null -ne (Get-WorkspaceRoot)
}

function Get-WorkspaceConfigFile {
    $workspaceRoot = Get-WorkspaceRoot
    if (-not $workspaceRoot) {
        return $null
    }
    
    # Check all possible locations
    $locations = @(
        (Join-Path $workspaceRoot "scripts/powershell/workspace.yaml"),
        (Join-Path $workspaceRoot ".specify/workspace.yaml"),
        (Join-Path $workspaceRoot "workspace.yaml")
    )
    
    foreach ($loc in $locations) {
        if (Test-Path $loc) {
            return $loc
        }
    }
    return $null
}

function Get-WorkspaceConfig {
    param(
        [string]$Key,
        [string]$Default = ""
    )
    
    $configFile = Get-WorkspaceConfigFile
    if (-not $configFile) {
        return $Default
    }
    
    try {
        $content = Get-Content $configFile -Raw
        # Simple YAML parser for flat keys
        if ($content -match "(?m)^${Key}:\s*[`"']?(.+?)[`"']?\s*$") {
            return $matches[1].Trim()
        }
    } catch {
        # Ignore parse errors
    }
    return $Default
}

function Get-SpecsDir {
    if (Test-WorkspaceMode) {
        $workspaceRoot = Get-WorkspaceRoot
        $strategy = Get-WorkspaceConfig -Key "spec_strategy" -Default "centralized"
        
        switch ($strategy) {
            "centralized" {
                $specsDir = Get-WorkspaceConfig -Key "specs_dir" -Default (Join-Path $workspaceRoot "specs")
                return $specsDir
            }
            "distributed" {
                $projectRoot = Get-ProjectRoot
                if ($projectRoot) {
                    return (Join-Path $projectRoot "specs")
                }
            }
        }
        return (Join-Path $workspaceRoot "specs")
    } else {
        # Legacy: specs in repo root
        $repoRoot = Get-RepoRoot
        return (Join-Path $repoRoot "specs")
    }
}

# =============================================================================
# PROJECT DETECTION (Multi-repo support)
# =============================================================================

function Get-ProjectName {
    # Check explicit env var first
    if ($env:SPECIFY_PROJECT) {
        return $env:SPECIFY_PROJECT
    }
    
    # If in a git repo, extract project name from repo path
    try {
        $repoRoot = git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $repoRoot) {
            return (Split-Path $repoRoot -Leaf)
        }
    } catch {
        # Git not available
    }
    
    # Check if we're in workspace mode and require explicit project
    if (Test-WorkspaceMode) {
        $behavior = Get-WorkspaceConfig -Key "no_project_behavior" -Default "error"
        
        switch ($behavior) {
            "error" {
                Write-Error "ERROR: No project specified. Use --project <name> or set SPECIFY_PROJECT"
                return $null
            }
            "prompt" {
                Write-Error "ERROR: No project specified. Use --project <name> or set SPECIFY_PROJECT"
                return $null
            }
            "current" {
                return (Split-Path (Get-Location) -Leaf)
            }
        }
    }
    
    return $null
}

function Get-ProjectRoot {
    # Check explicit env var first
    if ($env:SPECIFY_PROJECT_ROOT) {
        return $env:SPECIFY_PROJECT_ROOT
    }
    
    # If in a git repo, use it
    try {
        $repoRoot = git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $repoRoot) {
            return $repoRoot
        }
    } catch {
        # Git not available
    }
    
    # If SPECIFY_PROJECT is set, resolve it within workspace
    if ($env:SPECIFY_PROJECT) {
        $workspaceRoot = Get-WorkspaceRoot
        if ($workspaceRoot) {
            $projectPath = Join-Path $workspaceRoot $env:SPECIFY_PROJECT
            if (Test-Path $projectPath) {
                return $projectPath
            }
        }
    }
    
    Write-Error "ERROR: Cannot determine project root. Set SPECIFY_PROJECT or cd into a repo."
    return $null
}

function Get-Projects {
    param([switch]$Json)
    
    $workspaceRoot = Get-WorkspaceRoot
    if (-not $workspaceRoot) {
        if ($Json) {
            return "[]"
        }
        return @()
    }
    
    # Patterns to exclude
    $excludePatterns = @(
        'node_modules', '.git', '.specify', '.opencode', 'specs',
        '__pycache__', '.venv', 'venv', 'scripts', 'templates',
        'memory', 'docs', 'media', '.claude', '.cursor', '.github'
    )
    
    $projects = @()
    Get-ChildItem -Path $workspaceRoot -Directory | Where-Object {
        $name = $_.Name
        -not ($name.StartsWith('.')) -and
        -not ($excludePatterns -contains $name) -and
        ((Test-Path (Join-Path $_.FullName ".git")) -or (Test-Path (Join-Path $_.FullName ".specify")))
    } | ForEach-Object {
        $projects += $_.Name
    }
    
    if ($Json) {
        return ($projects | ConvertTo-Json -Compress)
    }
    return $projects
}

function Get-ProjectsDetailed {
    $workspaceRoot = Get-WorkspaceRoot
    if (-not $workspaceRoot) {
        return @()
    }
    
    $excludePatterns = @(
        'node_modules', '.git', '.specify', '.opencode', 'specs',
        '__pycache__', '.venv', 'venv', 'scripts', 'templates',
        'memory', 'docs', 'media', '.claude', '.cursor', '.github'
    )
    
    $projects = @()
    Get-ChildItem -Path $workspaceRoot -Directory | Where-Object {
        $name = $_.Name
        -not ($name.StartsWith('.')) -and
        -not ($excludePatterns -contains $name) -and
        ((Test-Path (Join-Path $_.FullName ".git")) -or (Test-Path (Join-Path $_.FullName ".specify")))
    } | ForEach-Object {
        $dir = $_.FullName
        $name = $_.Name
        $hasGit = $false
        $remoteUrl = ""
        $branch = ""
        $isWorktree = $false
        $mainWorktree = ""
        
        try {
            $gitDir = git -C $dir rev-parse --git-dir 2>$null
            if ($LASTEXITCODE -eq 0) {
                $hasGit = $true
                $remoteUrl = git -C $dir remote get-url origin 2>$null
                if ($LASTEXITCODE -ne 0) { $remoteUrl = "" }
                $branch = git -C $dir rev-parse --abbrev-ref HEAD 2>$null
                if ($LASTEXITCODE -ne 0) { $branch = "" }
                
                if ($gitDir -match '\.git[/\\]worktrees[/\\]') {
                    $isWorktree = $true
                    $commonDir = git -C $dir rev-parse --path-format=absolute --git-common-dir 2>$null
                    if ($LASTEXITCODE -eq 0 -and $commonDir) {
                        $mainWorktree = Split-Path (Split-Path $commonDir -Parent) -Leaf
                    }
                }
            }
        } catch { }
        
        $projects += [PSCustomObject]@{
            name = $name
            has_git = $hasGit
            remote_url = $remoteUrl
            branch = $branch
            is_worktree = $isWorktree
            main_worktree = $mainWorktree
        }
    }
    
    return $projects
}

# =============================================================================
# FEATURE SHORTHAND PARSING
# =============================================================================

function Parse-FeatureShorthand {
    param([string]$Ref)
    
    # Parse "project-NNN" or "project-NNN-description" format
    if ($Ref -match '^([a-zA-Z][a-zA-Z0-9_.-]*)-(\d{3})(?:-(.*))?$') {
        return [PSCustomObject]@{
            Project = $matches[1]
            Number = $matches[2]
            Description = $matches[3]
            Valid = $true
        }
    }
    
    # Legacy format: "NNN-description"
    if ($Ref -match '^(\d{3})-(.+)$') {
        return [PSCustomObject]@{
            Project = $null
            Number = $matches[1]
            Description = $matches[2]
            Valid = $true
        }
    }
    
    return [PSCustomObject]@{
        Valid = $false
    }
}

function Get-WorkspaceFeatures {
    param([switch]$Json)
    
    $specsDir = Get-SpecsDir
    if (-not (Test-Path $specsDir)) {
        if ($Json) {
            return "[]"
        }
        return @()
    }
    
    $features = @()
    
    if (Test-WorkspaceMode) {
        # Workspace mode: specs/project/feature/
        Get-ChildItem -Path $specsDir -Directory | ForEach-Object {
            $projectName = $_.Name
            Get-ChildItem -Path $_.FullName -Directory | ForEach-Object {
                if ($_.Name -match '^(\d{3})-') {
                    $featureNum = $matches[1]
                    $features += [PSCustomObject]@{
                        Shorthand = "$projectName-$featureNum"
                        Project = $projectName
                        Feature = $_.Name
                        Path = $_.FullName
                    }
                }
            }
        }
    } else {
        # Legacy mode: specs/feature/
        Get-ChildItem -Path $specsDir -Directory | ForEach-Object {
            if ($_.Name -match '^(\d{3})-') {
                $features += [PSCustomObject]@{
                    Shorthand = $_.Name
                    Project = $null
                    Feature = $_.Name
                    Path = $_.FullName
                }
            }
        }
    }
    
    if ($Json) {
        return ($features | ConvertTo-Json -Compress)
    }
    return $features
}

function Get-NextWorkspaceFeatureNumber {
    param([string]$Project)
    
    $specsDir = Get-SpecsDir
    $highest = 0
    
    if (Test-WorkspaceMode -and $Project) {
        $projectSpecsDir = Join-Path $specsDir $Project
        if (Test-Path $projectSpecsDir) {
            Get-ChildItem -Path $projectSpecsDir -Directory | ForEach-Object {
                if ($_.Name -match '^(\d{3})-') {
                    $num = [int]$matches[1]
                    if ($num -gt $highest) { $highest = $num }
                }
            }
        }
        
        # Also check branches if git available
        try {
            $branches = git branch -a 2>$null
            if ($LASTEXITCODE -eq 0) {
                foreach ($branch in $branches) {
                    $cleanBranch = $branch.Trim() -replace '^\*?\s+', '' -replace '^remotes/[^/]+/', ''
                    # Match project-NNN-* pattern
                    if ($cleanBranch -match "^$Project-(\d{3})-") {
                        $num = [int]$matches[1]
                        if ($num -gt $highest) { $highest = $num }
                    }
                }
            }
        } catch {
            # Ignore git errors
        }
    } else {
        # Legacy mode - check all features
        if (Test-Path $specsDir) {
            Get-ChildItem -Path $specsDir -Directory | ForEach-Object {
                if ($_.Name -match '^(\d{3})-') {
                    $num = [int]$matches[1]
                    if ($num -gt $highest) { $highest = $num }
                }
            }
        }
    }
    
    return $highest + 1
}

# =============================================================================
# LEGACY FUNCTIONS (backward compatibility)
# =============================================================================

function Get-RepoRoot {
    try {
        $result = git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $result
        }
    } catch {
        # Git command failed
    }
    
    # Fall back to script location for non-git repos
    return (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
}

function Get-CurrentBranch {
    # First check if SPECIFY_FEATURE environment variable is set
    if ($env:SPECIFY_FEATURE) {
        return $env:SPECIFY_FEATURE
    }
    
    # Then check git if available
    try {
        $result = git rev-parse --abbrev-ref HEAD 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $result
        }
    } catch {
        # Git command failed
    }
    
    # For non-git repos, try to find the latest feature directory
    $specsDir = Get-SpecsDir
    
    if (Test-Path $specsDir) {
        $latestFeature = ""
        $highest = 0
        
        Get-ChildItem -Path $specsDir -Directory | ForEach-Object {
            if ($_.Name -match '^(\d{3})-') {
                $num = [int]$matches[1]
                if ($num -gt $highest) {
                    $highest = $num
                    $latestFeature = $_.Name
                }
            }
        }
        
        if ($latestFeature) {
            return $latestFeature
        }
    }
    
    # Final fallback
    return "main"
}

function Test-HasGit {
    try {
        git rev-parse --show-toplevel 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Test-FeatureBranch {
    param(
        [string]$Branch,
        [bool]$HasGit = $true
    )
    
    # For non-git repos, we can't enforce branch naming but still provide output
    if (-not $HasGit) {
        Write-Warning "[specify] Warning: Git repository not detected; skipped branch validation"
        return $true
    }
    
    # In workspace mode, branch format is project-NNN-description
    if (Test-WorkspaceMode) {
        if ($Branch -match '^[a-zA-Z][a-zA-Z0-9_.-]*-[0-9]{3}-') {
            return $true
        }
    }
    
    # Legacy format: NNN-description
    if ($Branch -match '^[0-9]{3}-') {
        return $true
    }
    
    Write-Output "ERROR: Not on a feature branch. Current branch: $Branch"
    Write-Output "Feature branches should be named like: 001-feature-name (legacy) or project-001-feature-name (workspace)"
    return $false
}

function Get-FeatureDir {
    param(
        [string]$RepoRoot,
        [string]$Branch,
        [string]$Project = $null
    )
    
    if (Test-WorkspaceMode -and $Project) {
        $specsDir = Get-SpecsDir
        return (Join-Path $specsDir "$Project/$Branch")
    }
    
    Join-Path $RepoRoot "specs/$Branch"
}

function Get-FeaturePathsEnv {
    param([string]$Project = $null)
    
    $repoRoot = Get-RepoRoot
    $currentBranch = Get-CurrentBranch
    $hasGit = Test-HasGit
    $featureDir = Get-FeatureDir -RepoRoot $repoRoot -Branch $currentBranch -Project $Project
    
    [PSCustomObject]@{
        REPO_ROOT     = $repoRoot
        CURRENT_BRANCH = $currentBranch
        HAS_GIT       = $hasGit
        FEATURE_DIR   = $featureDir
        FEATURE_SPEC  = Join-Path $featureDir 'spec.md'
        IMPL_PLAN     = Join-Path $featureDir 'plan.md'
        TASKS         = Join-Path $featureDir 'tasks.md'
        RESEARCH      = Join-Path $featureDir 'research.md'
        DATA_MODEL    = Join-Path $featureDir 'data-model.md'
        QUICKSTART    = Join-Path $featureDir 'quickstart.md'
        CONTRACTS_DIR = Join-Path $featureDir 'contracts'
        WORKSPACE_MODE = Test-WorkspaceMode
        PROJECT       = $Project
    }
}

function Test-FileExists {
    param([string]$Path, [string]$Description)
    if (Test-Path -Path $Path -PathType Leaf) {
        Write-Output "  ✓ $Description"
        return $true
    } else {
        Write-Output "  ✗ $Description"
        return $false
    }
}

function Test-DirHasFiles {
    param([string]$Path, [string]$Description)
    if ((Test-Path -Path $Path -PathType Container) -and (Get-ChildItem -Path $Path -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Select-Object -First 1)) {
        Write-Output "  ✓ $Description"
        return $true
    } else {
        Write-Output "  ✗ $Description"
        return $false
    }
}
