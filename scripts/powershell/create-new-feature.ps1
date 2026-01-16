#!/usr/bin/env pwsh
# Create a new feature
# Version: 2.0.0 - Multi-repository workspace support
[CmdletBinding()]
param(
    [switch]$Json,
    [string]$ShortName,
    [int]$Number = 0,
    [string]$Project,
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FeatureDescription
)
$ErrorActionPreference = 'Stop'

# Source common functions
. "$PSScriptRoot/common.ps1"

# Show help if requested
if ($Help) {
    Write-Host "Usage: ./create-new-feature.ps1 [-Json] [-ShortName <name>] [-Number N] [-Project <name>] <feature description>"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Json               Output in JSON format"
    Write-Host "  -ShortName <name>   Provide a custom short name (2-4 words) for the branch"
    Write-Host "  -Number N           Specify branch number manually (overrides auto-detection)"
    Write-Host "  -Project <name>     Project name (required in workspace mode)"
    Write-Host "  -Help               Show this help message"
    Write-Host ""
    Write-Host "Workspace Mode:"
    Write-Host "  When workspace.yaml is detected, features are created with project prefix:"
    Write-Host "    Branch: project-001-feature-name"
    Write-Host "    Specs: {workspace}/specs/project/001-feature-name/"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  # Legacy mode (single repo)"
    Write-Host "  ./create-new-feature.ps1 'Add user authentication system' -ShortName 'user-auth'"
    Write-Host ""
    Write-Host "  # Workspace mode (multi-repo)"
    Write-Host "  ./create-new-feature.ps1 -Project myrepo 'Add user authentication system'"
    exit 0
}

# Check if feature description provided
if (-not $FeatureDescription -or $FeatureDescription.Count -eq 0) {
    Write-Error "Usage: ./create-new-feature.ps1 [-Json] [-ShortName <name>] [-Project <name>] <feature description>"
    exit 1
}

$featureDesc = ($FeatureDescription -join ' ').Trim()

# Detect workspace mode
$isWorkspaceMode = Test-WorkspaceMode
$workspaceRoot = $null

if ($isWorkspaceMode) {
    $workspaceRoot = Get-WorkspaceRoot
    
    # In workspace mode, project is required
    if (-not $Project) {
        # Try to get from env
        if ($env:SPECIFY_PROJECT) {
            $Project = $env:SPECIFY_PROJECT
        } else {
            Write-Error "ERROR: --project is required in workspace mode. Available projects:"
            $projects = Get-Projects
            foreach ($p in $projects) {
                Write-Error "  - $p"
            }
            exit 1
        }
    }
    
    # Validate project exists
    $projectPath = Join-Path $workspaceRoot $Project
    if (-not (Test-Path $projectPath)) {
        Write-Error "ERROR: Project '$Project' not found in workspace: $workspaceRoot"
        Write-Error "Available projects:"
        $projects = Get-Projects
        foreach ($p in $projects) {
            Write-Error "  - $p"
        }
        exit 1
    }
}

# Resolve repository root
function Find-RepositoryRoot {
    param(
        [string]$StartDir,
        [string[]]$Markers = @('.git', '.specify')
    )
    $current = Resolve-Path $StartDir
    while ($true) {
        foreach ($marker in $Markers) {
            if (Test-Path (Join-Path $current $marker)) {
                return $current
            }
        }
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) {
            return $null
        }
        $current = $parent
    }
}

function Get-HighestNumberFromSpecs {
    param([string]$SpecsDir, [string]$ProjectPrefix = "")
    
    $highest = 0
    if (Test-Path $SpecsDir) {
        Get-ChildItem -Path $SpecsDir -Directory | ForEach-Object {
            $name = $_.Name
            if ($ProjectPrefix) {
                # Workspace mode: check for project-NNN-* branches in project subfolder
                if ($name -match '^(\d+)') {
                    $num = [int]$matches[1]
                    if ($num -gt $highest) { $highest = $num }
                }
            } else {
                # Legacy mode: check for NNN-* pattern
                if ($name -match '^(\d+)') {
                    $num = [int]$matches[1]
                    if ($num -gt $highest) { $highest = $num }
                }
            }
        }
    }
    return $highest
}

function Get-HighestNumberFromBranches {
    param([string]$ProjectPrefix = "")
    
    $highest = 0
    try {
        $branches = git branch -a 2>$null
        if ($LASTEXITCODE -eq 0) {
            foreach ($branch in $branches) {
                $cleanBranch = $branch.Trim() -replace '^\*?\s+', '' -replace '^remotes/[^/]+/', ''
                
                if ($ProjectPrefix) {
                    # Workspace mode: match project-NNN-* pattern
                    if ($cleanBranch -match "^$ProjectPrefix-(\d+)-") {
                        $num = [int]$matches[1]
                        if ($num -gt $highest) { $highest = $num }
                    }
                } else {
                    # Legacy mode: match NNN-* pattern
                    if ($cleanBranch -match '^(\d+)-') {
                        $num = [int]$matches[1]
                        if ($num -gt $highest) { $highest = $num }
                    }
                }
            }
        }
    } catch {
        Write-Verbose "Could not check Git branches: $_"
    }
    return $highest
}

function Get-NextBranchNumber {
    param(
        [string]$SpecsDir,
        [string]$ProjectPrefix = ""
    )

    # Fetch all remotes to get latest branch info
    try {
        git fetch --all --prune 2>$null | Out-Null
    } catch {
        # Ignore fetch errors
    }

    $highestBranch = Get-HighestNumberFromBranches -ProjectPrefix $ProjectPrefix
    $highestSpec = Get-HighestNumberFromSpecs -SpecsDir $SpecsDir -ProjectPrefix $ProjectPrefix

    $maxNum = [Math]::Max($highestBranch, $highestSpec)
    return $maxNum + 1
}

function ConvertTo-CleanBranchName {
    param([string]$Name)
    return $Name.ToLower() -replace '[^a-z0-9]', '-' -replace '-{2,}', '-' -replace '^-', '' -replace '-$', ''
}

# Determine repository context
if ($isWorkspaceMode) {
    $projectPath = Join-Path $workspaceRoot $Project
    $repoRoot = $projectPath
    
    # Check if project has git
    $hasGit = Test-Path (Join-Path $projectPath ".git")
} else {
    $fallbackRoot = Find-RepositoryRoot -StartDir $PSScriptRoot
    if (-not $fallbackRoot) {
        Write-Error "Error: Could not determine repository root."
        exit 1
    }

    try {
        $repoRoot = git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0) {
            $hasGit = $true
        } else {
            throw "Git not available"
        }
    } catch {
        $repoRoot = $fallbackRoot
        $hasGit = $false
    }
}

# Determine specs directory
if ($isWorkspaceMode) {
    $specsDir = Get-SpecsDir
    $projectSpecsDir = Join-Path $specsDir $Project
    New-Item -ItemType Directory -Path $projectSpecsDir -Force | Out-Null
} else {
    Set-Location $repoRoot
    $specsDir = Join-Path $repoRoot 'specs'
    New-Item -ItemType Directory -Path $specsDir -Force | Out-Null
}

# Function to generate branch name with stop word filtering
function Get-BranchName {
    param([string]$Description)
    
    $stopWords = @(
        'i', 'a', 'an', 'the', 'to', 'for', 'of', 'in', 'on', 'at', 'by', 'with', 'from',
        'is', 'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had',
        'do', 'does', 'did', 'will', 'would', 'should', 'could', 'can', 'may', 'might', 'must', 'shall',
        'this', 'that', 'these', 'those', 'my', 'your', 'our', 'their',
        'want', 'need', 'add', 'get', 'set'
    )
    
    $cleanName = $Description.ToLower() -replace '[^a-z0-9\s]', ' '
    $words = $cleanName -split '\s+' | Where-Object { $_ }
    
    $meaningfulWords = @()
    foreach ($word in $words) {
        if ($stopWords -contains $word) { continue }
        if ($word.Length -ge 3) {
            $meaningfulWords += $word
        } elseif ($Description -match "\b$($word.ToUpper())\b") {
            $meaningfulWords += $word
        }
    }
    
    if ($meaningfulWords.Count -gt 0) {
        $maxWords = if ($meaningfulWords.Count -eq 4) { 4 } else { 3 }
        $result = ($meaningfulWords | Select-Object -First $maxWords) -join '-'
        return $result
    } else {
        $result = ConvertTo-CleanBranchName -Name $Description
        $fallbackWords = ($result -split '-') | Where-Object { $_ } | Select-Object -First 3
        return [string]::Join('-', $fallbackWords)
    }
}

# Generate branch name suffix
if ($ShortName) {
    $branchSuffix = ConvertTo-CleanBranchName -Name $ShortName
} else {
    $branchSuffix = Get-BranchName -Description $featureDesc
}

# Determine branch number
if ($Number -eq 0) {
    if ($isWorkspaceMode) {
        $Number = Get-NextBranchNumber -SpecsDir $projectSpecsDir -ProjectPrefix $Project
    } elseif ($hasGit) {
        $Number = Get-NextBranchNumber -SpecsDir $specsDir
    } else {
        $Number = (Get-HighestNumberFromSpecs -SpecsDir $specsDir) + 1
    }
}

$featureNum = ('{0:000}' -f $Number)

# Build branch name based on mode
if ($isWorkspaceMode) {
    $branchName = "$Project-$featureNum-$branchSuffix"
    $featureDirName = "$featureNum-$branchSuffix"
} else {
    $branchName = "$featureNum-$branchSuffix"
    $featureDirName = $branchName
}

# GitHub enforces a 244-byte limit on branch names
$maxBranchLength = 244
if ($branchName.Length -gt $maxBranchLength) {
    if ($isWorkspaceMode) {
        $prefixLen = $Project.Length + 1 + 3 + 1  # project + hyphen + number + hyphen
        $maxSuffixLength = $maxBranchLength - $prefixLen
    } else {
        $maxSuffixLength = $maxBranchLength - 4  # number + hyphen
    }
    
    $truncatedSuffix = $branchSuffix.Substring(0, [Math]::Min($branchSuffix.Length, $maxSuffixLength))
    $truncatedSuffix = $truncatedSuffix -replace '-$', ''
    
    $originalBranchName = $branchName
    if ($isWorkspaceMode) {
        $branchName = "$Project-$featureNum-$truncatedSuffix"
        $featureDirName = "$featureNum-$truncatedSuffix"
    } else {
        $branchName = "$featureNum-$truncatedSuffix"
        $featureDirName = $branchName
    }
    
    Write-Warning "[specify] Branch name exceeded GitHub's 244-byte limit"
    Write-Warning "[specify] Original: $originalBranchName ($($originalBranchName.Length) bytes)"
    Write-Warning "[specify] Truncated to: $branchName ($($branchName.Length) bytes)"
}

# Create git branch (if in project with git or not in workspace mode)
if ($hasGit) {
    if ($isWorkspaceMode) {
        # In workspace mode, create branch in project repo
        Push-Location $projectPath
        try {
            git checkout -b $branchName 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Failed to create git branch: $branchName"
            }
        } catch {
            Write-Warning "Failed to create git branch: $branchName"
        }
        Pop-Location
    } else {
        try {
            git checkout -b $branchName | Out-Null
        } catch {
            Write-Warning "Failed to create git branch: $branchName"
        }
    }
} else {
    Write-Warning "[specify] Warning: Git repository not detected; skipped branch creation for $branchName"
}

# Create feature directory
if ($isWorkspaceMode) {
    $featureDir = Join-Path $projectSpecsDir $featureDirName
} else {
    $featureDir = Join-Path $specsDir $featureDirName
}
New-Item -ItemType Directory -Path $featureDir -Force | Out-Null

# Copy spec template
if ($isWorkspaceMode) {
    $template = Join-Path $workspaceRoot '.specify/templates/spec-template.md'
} else {
    $template = Join-Path $repoRoot '.specify/templates/spec-template.md'
}
$specFile = Join-Path $featureDir 'spec.md'
if (Test-Path $template) { 
    Copy-Item $template $specFile -Force 
} else { 
    New-Item -ItemType File -Path $specFile | Out-Null 
}

# Set environment variables
$env:SPECIFY_FEATURE = $featureDirName
if ($isWorkspaceMode) {
    $env:SPECIFY_PROJECT = $Project
}

# Build output
$output = [PSCustomObject]@{ 
    BRANCH_NAME = $branchName
    SPEC_FILE = $specFile
    FEATURE_NUM = $featureNum
    HAS_GIT = $hasGit
    WORKSPACE_MODE = $isWorkspaceMode
}

if ($isWorkspaceMode) {
    $output | Add-Member -NotePropertyName PROJECT -NotePropertyValue $Project
    $output | Add-Member -NotePropertyName SHORTHAND -NotePropertyValue "$Project-$featureNum"
}

if ($Json) {
    $output | ConvertTo-Json -Compress
} else {
    Write-Output "BRANCH_NAME: $branchName"
    Write-Output "SPEC_FILE: $specFile"
    Write-Output "FEATURE_NUM: $featureNum"
    Write-Output "HAS_GIT: $hasGit"
    Write-Output "WORKSPACE_MODE: $isWorkspaceMode"
    if ($isWorkspaceMode) {
        Write-Output "PROJECT: $Project"
        Write-Output "SHORTHAND: $Project-$featureNum"
    }
    Write-Output "SPECIFY_FEATURE environment variable set to: $featureDirName"
}
