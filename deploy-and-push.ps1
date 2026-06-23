# Gov News GitHub Pages Deployment & Push Script
# Securely handles GitHub PAT authentication
# Date: 2026-06-20

param(
    [string]$GitHubPAT = $env:GITHUB_PAT,
    [string]$TargetDate = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd"),
    [string]$Mode = "update"
)

$ErrorActionPreference = "Stop"

# Configuration
$ProjectRoot = "D:\Gov-News-GitHub"
$GitHubPagesDir = "$ProjectRoot\gov-news-thailand"
$PublisherOutput = "$ProjectRoot\Document\${TargetDate}_News"
$SourceJson = "$PublisherOutput\${TargetDate}_news.json"
$GitHubRepo = "https://github.com/chiraleo2000/gov-news-thailand.git"
$DataDir = "$GitHubPagesDir\data"

# Display header
Write-Host "╔═════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Gov News GitHub Pages Auto-Deploy v2.0               ║" -ForegroundColor Cyan
Write-Host "║  PAT Authentication Ready                              ║" -ForegroundColor Cyan
Write-Host "╚═════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "📅 Target Date: $TargetDate" -ForegroundColor Yellow
Write-Host "📂 Mode: $Mode" -ForegroundColor Yellow
Write-Host ""

# Validate PAT
if ([string]::IsNullOrEmpty($GitHubPAT)) {
    Write-Host "❌ ERROR: GitHub PAT not provided!" -ForegroundColor Red
    Write-Host "   Set environment variable: GITHUB_PAT or pass -GitHubPAT parameter" -ForegroundColor Red
    exit 1
}

# Step 1: Verify source JSON exists
Write-Host "[1/5] Checking source JSON..." -ForegroundColor Blue
if (-not (Test-Path $SourceJson)) {
    Write-Host "❌ ERROR: Source JSON not found at $SourceJson" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Source found: ${TargetDate}_news.json ($(((Get-Item $SourceJson).Length/1KB).ToString('F1')) KB)" -ForegroundColor Green
Write-Host ""

# Step 2: Ensure git repo exists
Write-Host "[2/5] Preparing Git repository..." -ForegroundColor Blue
if (-not (Test-Path "$GitHubPagesDir\.git")) {
    Write-Host "   Cloning repository..." -ForegroundColor Cyan
    git clone $GitHubRepo $GitHubPagesDir 2>&1 | Out-Null
} else {
    Write-Host "   Repository exists, fetching latest..." -ForegroundColor Cyan
    Push-Location $GitHubPagesDir
    git fetch origin 2>&1 | Out-Null
    Pop-Location
}
Write-Host "✅ Repository ready at $GitHubPagesDir" -ForegroundColor Green
Write-Host ""

# Step 3: Sync data files
Write-Host "[3/5] Syncing data files..." -ForegroundColor Blue
if (-not (Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}
Copy-Item $SourceJson "$DataDir\${TargetDate}_news.json" -Force
Write-Host "✅ Copied: ${TargetDate}_news.json → data folder" -ForegroundColor Green
Write-Host ""

# Step 4: Update manifest.json
Write-Host "[4/5] Updating manifest.json..." -ForegroundColor Blue
$ManifestPath = "$DataDir\manifest.json"
if (-not (Test-Path $ManifestPath)) {
    Write-Host "   Creating new manifest..." -ForegroundColor Cyan
    $Manifest = @("${TargetDate}_news.json")
} else {
    Write-Host "   Updating existing manifest..." -ForegroundColor Cyan
    $Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json

    # Remove if already exists (to move to front)
    $Manifest = @($Manifest | Where-Object { $_ -ne "${TargetDate}_news.json" })

    # Add to front
    $Manifest = @("${TargetDate}_news.json") + @($Manifest) | Select-Object -First 30
}
$Manifest | ConvertTo-Json | Set-Content $ManifestPath -Encoding UTF8
Write-Host "✅ Manifest updated with ${TargetDate}_news.json at index 0" -ForegroundColor Green
Write-Host ""

# Step 5: Configure Git and Push
Write-Host "[5/5] Committing and pushing to GitHub..." -ForegroundColor Blue
Push-Location $GitHubPagesDir

try {
    # Configure git user
    git config user.email "chiraleo2000@users.noreply.github.com" 2>&1 | Out-Null
    git config user.name "chiraleo2000" 2>&1 | Out-Null

    # Set remote with PAT authentication
    $AuthUrl = "https://chiraleo2000:$GitHubPAT@github.com/chiraleo2000/gov-news-thailand.git"
    git remote set-url origin $AuthUrl 2>&1 | Out-Null

    # Add files
    git add "data/${TargetDate}_news.json" "data/manifest.json" 2>&1 | Out-Null

    # Check if there are changes
    $Status = git status --porcelain 2>&1

    if ($Status) {
        Write-Host "   Creating commit..." -ForegroundColor Cyan
        git commit -m "Deploy: ${TargetDate}_news.json" 2>&1 | Out-Null

        Write-Host "   Pushing to origin/master..." -ForegroundColor Cyan
        $PushOutput = git push origin master 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Successfully pushed to GitHub!" -ForegroundColor Green
        } else {
            throw "Push failed: $PushOutput"
        }
    } else {
        Write-Host "✅ No changes to commit (already up to date)" -ForegroundColor Green
    }

} catch {
    Write-Host "❌ ERROR: $_" -ForegroundColor Red
    exit 1
} finally {
    # Clear sensitive data from memory
    $AuthUrl = $null
    Pop-Location
}

Write-Host ""
Write-Host "╔═════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  ✅ DEPLOYMENT COMPLETE                                 ║" -ForegroundColor Green
Write-Host "╚═════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "📱 Site URL: https://chiraleo2000.github.io/gov-news-thailand/" -ForegroundColor Cyan
Write-Host "📊 Data: data/${TargetDate}_news.json deployed" -ForegroundColor Cyan
Write-Host "🕐 Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host ""
