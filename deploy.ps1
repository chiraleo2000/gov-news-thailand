#!/usr/bin/env pwsh
# ============================================================
# Gov-News GitHub Deploy Script v3.0
# Auto-deploy daily news JSON to GitHub Pages
# Designed for: Kiro automated runs / scheduled tasks
# ============================================================
# Usage:
#   pwsh -File deploy.ps1              (auto-detect latest date)
#   pwsh -File deploy.ps1 -Date "2026-07-04"
# ============================================================

param(
    [string]$Date = ""
)

$ErrorActionPreference = "Continue"
$PROJECT_ROOT = "d:\Gov-News-GitHub"
$GITHUB_PAGES = "d:\Gov-News-GitHub\gov-news-thailand"
$DOCUMENT_DIR = "d:\Gov-News-GitHub\Document"
$DEST_DATA = "$GITHUB_PAGES\data"

Write-Host "============================================================"
Write-Host " Gov-News GitHub Deploy v3.0"
Write-Host " $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "============================================================"

# --- Step 0: Determine TARGET_DATE ---
if (-not $Date) {
    $latest = Get-ChildItem $DOCUMENT_DIR -Directory -Filter "*_News" |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($latest) {
        $Date = $latest.Name -replace "_News$", ""
        Write-Host "[AUTO] Detected target date: $Date"
    } else {
        Write-Host "[ERROR] No *_News folder found in $DOCUMENT_DIR"
        exit 1
    }
} else {
    Write-Host "[PARAM] Target date: $Date"
}

$SOURCE_JSON = "$DOCUMENT_DIR\${Date}_News\${Date}_news.json"
$DEST_JSON = "$DEST_DATA\${Date}_news.json"

# --- Step 1: Clear ALL git locks aggressively ---
Write-Host "[LOCK] Cleaning git locks..."
Get-ChildItem "$GITHUB_PAGES\.git" -Recurse -Filter "*.lock" -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    Write-Host "[LOCK] Removed $($_.FullName)"
}

# --- Step 2: Copy source JSON to data/ ---
if (-not (Test-Path $SOURCE_JSON)) {
    if (Test-Path $DEST_JSON) {
        Write-Host "[OK] Source not found but already exists in data/: $DEST_JSON"
    } else {
        Write-Host "[ERROR] No source JSON found: $SOURCE_JSON"
        exit 1
    }
} else {
    Copy-Item $SOURCE_JSON $DEST_JSON -Force
    Write-Host "[COPY] $SOURCE_JSON -> data/${Date}_news.json"
}

# --- Step 3: Update manifest.json ---
$manifestPath = "$DEST_DATA\manifest.json"
$entry = "${Date}_news.json"

try {
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
} catch {
    Write-Host "[WARN] manifest.json parse failed, rebuilding..."
    $manifest = @()
}

if ($manifest -notcontains $entry) {
    $manifest = @($entry) + @($manifest)
    $manifest | ConvertTo-Json | Set-Content $manifestPath -Encoding UTF8
    Write-Host "[MANIFEST] Added $entry at index 0 (total: $($manifest.Count))"
} else {
    Write-Host "[MANIFEST] Already contains $entry ($($manifest.Count) entries)"
}

# --- Step 3.5: Validate manifest ---
try {
    $check = Get-Content $manifestPath -Raw | ConvertFrom-Json
    if ($check.Count -lt 1) { throw "Empty manifest" }
    Write-Host "[VALIDATE] manifest.json OK ($($check.Count) entries, latest: $($check[0]))"
} catch {
    Write-Host "[ERROR] Manifest invalid after update: $_"
    Write-Host "[FIX] Rebuilding from data/ folder..."
    $files = Get-ChildItem $DEST_DATA -Filter "*_news.json" -Name | Sort-Object -Descending
    $files | ConvertTo-Json | Set-Content $manifestPath -Encoding UTF8
    Write-Host "[FIX] Rebuilt manifest ($($files.Count) entries)"
}

# --- Step 3.6: Verify .nojekyll ---
$nojekyll = "$GITHUB_PAGES\.nojekyll"
if (-not (Test-Path $nojekyll)) {
    New-Item $nojekyll -ItemType File -Force | Out-Null
    Write-Host "[FIX] Created .nojekyll"
}

# --- Step 4: Git push (with full retry logic) ---
Push-Location $GITHUB_PAGES

# Clear locks again before git operations
Get-ChildItem ".git" -Recurse -Filter "*.lock" -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
}

# Stage all changes
git add . 2>&1 | Out-Null

$status = git status --porcelain 2>&1
if (-not $status) {
    # Check if there are unpushed commits
    $ahead = git rev-list --count "origin/master..HEAD" 2>&1
    if ($ahead -gt 0) {
        Write-Host "[GIT] No new changes but $ahead unpushed commit(s). Pushing..."
    } else {
        Write-Host "[GIT] Nothing to commit, already up to date with remote."
        Pop-Location
        Write-Host ""
        Write-Host "============================================================"
        Write-Host " ALREADY UP TO DATE - No deployment needed"
        Write-Host "============================================================"
        exit 0
    }
} else {
    git commit -m "Add news $Date" 2>&1 | Out-Null
    Write-Host "[GIT] Committed: Add news $Date"
}

# Push with retry escalation
$maxRetries = 5
$pushed = $false

for ($i = 1; $i -le $maxRetries; $i++) {
    # Clear locks before each attempt
    Get-ChildItem ".git" -Recurse -Filter "*.lock" -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }

    Write-Host "[GIT] Push attempt $i/$maxRetries..."
    $pushOutput = git push origin master 2>&1
    if ($LASTEXITCODE -eq 0) {
        $pushed = $true
        Write-Host "[GIT] Push SUCCESS"
        break
    }

    Write-Host "[GIT] Push failed: $pushOutput"

    if ($i -lt $maxRetries) {
        switch ($i) {
            1 {
                Write-Host "[RETRY] Pull --rebase..."
                git pull --rebase origin master 2>&1 | Out-Null
            }
            2 {
                Write-Host "[RETRY] Fetch + reset soft..."
                git fetch origin 2>&1 | Out-Null
                git reset --soft origin/master 2>&1 | Out-Null
                git add . 2>&1 | Out-Null
                git commit -m "Add news $Date" 2>&1 | Out-Null
            }
            3 {
                Write-Host "[RETRY] Pull with allow-unrelated-histories..."
                git pull origin master --allow-unrelated-histories 2>&1 | Out-Null
                git add . 2>&1 | Out-Null
                git commit -m "Add news $Date" --allow-empty 2>&1 | Out-Null
            }
            4 {
                Write-Host "[RETRY] Will force push on next attempt..."
            }
        }
        Start-Sleep -Seconds 2
    }
}

if (-not $pushed) {
    Write-Host "[GIT] All normal retries failed. Force pushing..."
    git push -f origin master 2>&1
    if ($LASTEXITCODE -eq 0) {
        $pushed = $true
        Write-Host "[GIT] Force push SUCCESS"
    } else {
        Write-Host "[ERROR] Force push FAILED. Check network/auth."
        Pop-Location
        exit 1
    }
}

Pop-Location

# --- Step 5: Report ---
Write-Host ""
Write-Host "============================================================"
Write-Host " DEPLOYMENT COMPLETE"
Write-Host "============================================================"
Write-Host " Date:       $Date"
Write-Host " Git Push:   $(if($pushed){'SUCCESS'}else{'FAILED'})"
Write-Host " Site:       https://chiraleo2000.github.io/gov-news-thailand/"
Write-Host " Time:       $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "============================================================"

exit 0
