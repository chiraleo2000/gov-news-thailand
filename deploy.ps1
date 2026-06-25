#!/usr/bin/env pwsh
# ============================================================
# Gov-News GitHub Deploy Script v2.0
# Purpose: Push daily news JSON to GitHub Pages + sync OneDrive
# Designed for: Claude Schedule / Kiro automated runs
# ============================================================
# Usage: pwsh -File deploy.ps1 [-Date "2026-06-24"]
# If no -Date specified, uses the latest JSON in Document/
# ============================================================

param(
    [string]$Date = ""
)

$ErrorActionPreference = "Continue"
$PROJECT_ROOT = "d:\Gov-News-GitHub"
$GITHUB_PAGES = "d:\Gov-News-GitHub\gov-news-thailand"
$DOCUMENT_DIR = "d:\Gov-News-GitHub\Document"
$ONEDRIVE_DIR = "$env:USERPROFILE\OneDrive - Betimes Solutions\Gov-News"
$DEST_DATA = "$GITHUB_PAGES\data"

Write-Host "============================================================"
Write-Host " Gov-News GitHub Deploy v2.0"
Write-Host " $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "============================================================"

# --- Step 0: Determine TARGET_DATE ---
if (-not $Date) {
    # Auto-detect: find latest *_News folder in Document/
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

# --- Step 1: Clear git locks ---
@("index.lock", "HEAD.lock", "refs\heads\master.lock") | ForEach-Object {
    $lock = "$GITHUB_PAGES\.git\$_"
    if (Test-Path $lock) { Remove-Item $lock -Force; Write-Host "[LOCK] Removed $_" }
}

# --- Step 2: Check source JSON ---
if (-not (Test-Path $SOURCE_JSON)) {
    Write-Host "[WARN] Source not found: $SOURCE_JSON"
    Write-Host "[WARN] Attempting fallback from Articles..."
    # Fallback: check if already in data/ from a previous copy
    if (Test-Path $DEST_JSON) {
        Write-Host "[OK] Already exists in data/: $DEST_JSON"
    } else {
        Write-Host "[ERROR] No source JSON and no existing data. Abort."
        exit 1
    }
} else {
    Copy-Item $SOURCE_JSON $DEST_JSON -Force
    Write-Host "[COPY] $SOURCE_JSON -> data/"
}

# --- Step 3: Update manifest.json ---
$manifestPath = "$DEST_DATA\manifest.json"
$entry = "${Date}_news.json"
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
if ($manifest -notcontains $entry) {
    $manifest = @($entry) + $manifest
    $manifest | ConvertTo-Json | Set-Content $manifestPath -Encoding UTF8
    Write-Host "[MANIFEST] Added $entry at index 0"
} else {
    Write-Host "[MANIFEST] Already contains $entry"
}

# --- Step 3.5: Validate manifest ---
try {
    $check = Get-Content $manifestPath -Raw | ConvertFrom-Json
    if ($check.Count -lt 1) { throw "Empty manifest" }
    if ($check[0] -ne $entry -and $manifest -contains $entry) {
        Write-Host "[MANIFEST] OK (entry present, $($check.Count) total)"
    } else {
        Write-Host "[MANIFEST] Valid ($($check.Count) entries, latest: $($check[0]))"
    }
} catch {
    Write-Host "[ERROR] Manifest invalid: $_"
    # Rebuild from data/ folder
    $files = Get-ChildItem $DEST_DATA -Filter "*_news.json" -Name | Sort-Object -Descending
    $files | ConvertTo-Json | Set-Content $manifestPath -Encoding UTF8
    Write-Host "[FIX] Rebuilt manifest from data/ folder ($($files.Count) entries)"
}

# --- Step 3.6: Verify .nojekyll ---
$nojekyll = "$GITHUB_PAGES\.nojekyll"
if (-not (Test-Path $nojekyll)) {
    New-Item $nojekyll -ItemType File | Out-Null
    Write-Host "[FIX] Created .nojekyll"
}

# --- Step 4: Git add + commit + push ---
Set-Location $GITHUB_PAGES

# Sync with remote first (prevent rejected push)
Write-Host "[GIT] Fetching remote..."
git fetch origin 2>&1 | Out-Null

# Check if there are remote changes
$localHead = git rev-parse HEAD 2>&1
$remoteHead = git rev-parse origin/master 2>&1
if ($localHead -ne $remoteHead) {
    Write-Host "[GIT] Remote has changes, pulling with rebase..."
    git stash 2>&1 | Out-Null
    git pull --rebase origin master 2>&1
    git stash pop 2>&1 | Out-Null
}

git add .
$status = git status --porcelain
if (-not $status) {
    Write-Host "[GIT] Nothing to commit (already up to date)"
} else {
    git commit -m "Add news $Date"
    Write-Host "[GIT] Committed changes"
}

# Push with retry
$maxRetries = 5
$pushed = $false
for ($i = 1; $i -le $maxRetries; $i++) {
    Write-Host "[GIT] Push attempt $i/$maxRetries..."
    $result = git push origin master 2>&1
    if ($LASTEXITCODE -eq 0) {
        $pushed = $true
        Write-Host "[GIT] Push SUCCESS"
        break
    }
    Write-Host "[GIT] Push failed: $result"
    
    if ($i -lt $maxRetries) {
        Write-Host "[GIT] Retrying with pull --rebase..."
        git pull --rebase origin master 2>&1
        Start-Sleep -Seconds 2
    }
}

if (-not $pushed) {
    Write-Host "[GIT] All retries failed. Force pushing..."
    git push -f origin master 2>&1
    if ($LASTEXITCODE -eq 0) {
        $pushed = $true
        Write-Host "[GIT] Force push SUCCESS"
    } else {
        Write-Host "[ERROR] Force push also failed. Check network/auth."
        exit 1
    }
}

# --- Step 5: Sync to OneDrive ---
Write-Host ""
Write-Host "[ONEDRIVE] Syncing project to OneDrive..."
$onedriveTarget = $ONEDRIVE_DIR

if (Test-Path $onedriveTarget) {
    # Sync SKILL files
    Get-ChildItem "$PROJECT_ROOT\SKILL-*.md" | ForEach-Object {
        Copy-Item $_.FullName "$onedriveTarget\$($_.Name)" -Force
    }
    Write-Host "[ONEDRIVE] Synced SKILL files"
    
    # Sync Document folder (latest date only to save space)
    $docSrc = "$DOCUMENT_DIR\${Date}_News"
    $docDst = "$onedriveTarget\Document\${Date}_News"
    if (Test-Path $docSrc) {
        if (-not (Test-Path $docDst)) { New-Item $docDst -ItemType Directory -Force | Out-Null }
        Copy-Item "$docSrc\*" $docDst -Force -Recurse
        Write-Host "[ONEDRIVE] Synced Document/${Date}_News/"
    }
    
    # Sync News JSON to OneDrive
    $newsOneDrive = "$onedriveTarget\News"
    if (-not (Test-Path $newsOneDrive)) { New-Item $newsOneDrive -ItemType Directory -Force | Out-Null }
    if (Test-Path $SOURCE_JSON) {
        Copy-Item $SOURCE_JSON "$newsOneDrive\${Date}_news.json" -Force
        Write-Host "[ONEDRIVE] Synced ${Date}_news.json"
    }
} else {
    Write-Host "[ONEDRIVE] Path not found: $onedriveTarget (skip)"
}

# --- Step 6: Report ---
Write-Host ""
Write-Host "============================================================"
Write-Host " DEPLOYMENT COMPLETE"
Write-Host "============================================================"
Write-Host " Date:       $Date"
Write-Host " Git Push:   $(if($pushed){'SUCCESS'}else{'FAILED'})"
Write-Host " Site:       https://chiraleo2000.github.io/gov-news-thailand/"
Write-Host " OneDrive:   $onedriveTarget"
Write-Host " Time:       $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "============================================================"

exit 0
