# OneTimePushDates.ps1 - ONE-TIME catch-up for specific dates (not daily)
# Creates Document/{date}_News when missing, then commits+pushes each date.
# Usage: powershell -File OneTimePushDates.ps1 -Dates 2026-09-10,2026-09-11
param(
    [string[]]$Dates = @("2026-09-10", "2026-09-11")
)

$ErrorActionPreference = "Continue"
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Repo

$Parent = Split-Path -Parent $Repo
$LogDir = Join-Path $Parent "Logs"
if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$RunStamp = Get-Date -Format "yyyy-MM-dd"
$Log = Join-Path $LogDir ("gov-onetime-{0}.log" -f $RunStamp)
$Creator = Join-Path $Repo "create-news-json.py"
$Helper = Join-Path $Repo "update-manifest.py"
$Manifest = Join-Path $Repo "data\manifest.json"
$DocRoot = Join-Path $Parent "Document"

function Write-Log([string]$Message) {
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    Add-Content -LiteralPath $Log -Value $line -Encoding UTF8
}

function Clear-GitLocks {
    @(
        ".git\index.lock", ".git\HEAD.lock", ".git\config.lock",
        ".git\refs\heads\master.lock", ".git\shallow.lock"
    ) | ForEach-Object {
        $p = Join-Path $Repo $_
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
    }
    Get-ChildItem -Path (Join-Path $Repo ".git") -Recurse -Filter "*.lock" -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
}

function Push-OneDate([string]$Date) {
    Write-Log ("--- DATE {0} ---" -f $Date)
    $docNews = Join-Path $DocRoot ("{0}_News\{0}_news.json" -f $Date)
    $dataNews = Join-Path $Repo ("data\{0}_news.json" -f $Date)
    $briefing = Join-Path $DocRoot ("{0}_Facebook\{0}_facebook_briefing.json" -f $Date)
    $entry = "{0}_news.json" -f $Date

    $articlesRoot = Join-Path $Parent "News\Articles"
    $articleCount = 0
    if (Test-Path -LiteralPath $articlesRoot) {
        $needle1 = "\{0}\" -f $Date
        $needle2 = "/{0}/" -f $Date
        $articleCount = @(Get-ChildItem -LiteralPath $articlesRoot -Recurse -Filter "article.json" -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName.Contains($needle1) -or $_.FullName.Contains($needle2) }).Count
    }
    $hasDoc = Test-Path -LiteralPath $docNews
    $hasBrief = Test-Path -LiteralPath $briefing
    Write-Log ("  Document exists={0} briefing={1} articles={2}" -f $hasDoc, $hasBrief, $articleCount)

    if (-not $hasDoc) {
        if (-not $hasBrief -and $articleCount -eq 0) {
            Write-Log ("  ERROR: no Document and no sources for {0}" -f $Date)
            return $false
        }
        Write-Log ("  CREATE Document/{0}_News from Articles+Facebook" -f $Date)
        & python $Creator --date $Date --force 2>&1 | ForEach-Object { Write-Log ("    {0}" -f $_) }
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $docNews)) {
            Write-Log ("  ERROR: create failed for {0}" -f $Date)
            return $false
        }
    } else {
        Write-Log "  CREATE skipped — Document already exists (Claude)"
    }

    try {
        $payload = Get-Content -LiteralPath $docNews -Raw -Encoding UTF8 | ConvertFrom-Json
        $n = @($payload.posts).Count
        Write-Log ("  Ready posts={0} date={1}" -f $n, $payload.date)
        if ($n -lt 1) {
            Write-Log "  ERROR: 0 posts"
            return $false
        }
        if ($payload.date -ne $Date) {
            Write-Log ("  ERROR: payload.date={0} != {1}" -f $payload.date, $Date)
            return $false
        }
    } catch {
        Write-Log ("  ERROR: parse JSON: {0}" -f $_)
        return $false
    }

    Copy-Item -LiteralPath $docNews -Destination $dataNews -Force
    Write-Log ("  Copied to data/{0}" -f $entry)
    & python $Helper $Manifest $entry 2>&1 | ForEach-Object { Write-Log ("    {0}" -f $_) }
    if ($LASTEXITCODE -ne 0) {
        Write-Log "  ERROR: manifest update failed"
        return $false
    }

    Clear-GitLocks
    git add -- ("data/{0}" -f $entry) "data/manifest.json"
    git reset HEAD -- "*.ps1" "*.sh" 2>$null | Out-Null

    git diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
        git commit -m ("Add news {0}" -f $Date)
        if ($LASTEXITCODE -ne 0) {
            Write-Log "  ERROR: git commit failed"
            return $false
        }
        Write-Log ("  Committed Add news {0}" -f $Date)
    } else {
        Write-Log "  Nothing new to commit"
    }

    $pushed = $false
    git push origin master
    if ($LASTEXITCODE -eq 0) { $pushed = $true }
    if (-not $pushed) {
        Write-Log "  Push rejected — pull --rebase then retry"
        Clear-GitLocks
        git pull --rebase origin master
        if ($LASTEXITCODE -ne 0) {
            git rebase --abort 2>$null
            git pull origin master
        }
        git push origin master
        if ($LASTEXITCODE -eq 0) { $pushed = $true }
    }
    if (-not $pushed) {
        Write-Log "  ERROR: git push failed"
        return $false
    }

    git fetch origin 2>$null | Out-Null
    $ahead = 0
    try { $ahead = [int](git rev-list --count "origin/master..HEAD" 2>$null) } catch { $ahead = -1 }
    if ($ahead -ne 0) {
        Write-Log ("  ERROR: still ahead by {0}" -f $ahead)
        return $false
    }
    Write-Log ("  PASS {0}" -f $Date)
    return $true
}

$env:Path = "C:\Program Files\Git\cmd;C:\Program Files\Git\bin;" +
    "$env:LOCALAPPDATA\Python\bin;$env:LOCALAPPDATA\Programs\Python\Python312;" +
    "$env:LOCALAPPDATA\Programs\Python\Python311;$env:LOCALAPPDATA\Programs\Python\Python310;" +
    $env:Path
$env:HTTP_PROXY = ""
$env:HTTPS_PROXY = ""
$env:http_proxy = ""
$env:https_proxy = ""
$env:ALL_PROXY = ""
$env:all_proxy = ""
$env:NO_PROXY = "*"
$env:no_proxy = "*"

Write-Log "=== Gov-News OneTimePushDates.ps1 START ==="
Write-Log ("Repo={0}" -f $Repo)
Write-Log ("Dates={0}" -f ($Dates -join ", "))

if (-not (Test-Path -LiteralPath $Creator)) {
    Write-Log ("ERROR: missing {0}" -f $Creator)
    Write-Log "RESULT=FAIL"
    exit 1
}
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Log "ERROR: python not on PATH"
    Write-Log "RESULT=FAIL"
    exit 1
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Log "ERROR: git not on PATH"
    Write-Log "RESULT=FAIL"
    exit 1
}

$failed = @()
foreach ($d in $Dates) {
    $d = $d.Trim()
    if (-not $d) { continue }
    if (-not (Push-OneDate $d)) {
        $failed += $d
    }
}

# Re-enable nightly Retry if we paused it to avoid a git race with this one-time run
try {
    $retry = Get-ScheduledTask -TaskName "Gov-News-RetryPush" -ErrorAction SilentlyContinue
    if ($retry -and $retry.State -eq "Disabled") {
        Enable-ScheduledTask -TaskName "Gov-News-RetryPush" | Out-Null
        Write-Log "Re-enabled Gov-News-RetryPush for future nights"
    }
} catch {
    Write-Log ("WARN: could not re-enable Retry: {0}" -f $_)
}

if ($failed.Count -gt 0) {
    Write-Log ("RESULT=FAIL dates={0}" -f ($failed -join ", "))
    Write-Log "=== Gov-News OneTimePushDates.ps1 END ==="
    exit 1
}

Write-Log "RESULT=PASS"
Write-Log "SUCCESS https://chiraleo2000.github.io/gov-news-thailand/"
Write-Log "=== Gov-News OneTimePushDates.ps1 END ==="
exit 0
