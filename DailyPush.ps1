# DailyPush.ps1 - Gov-News Thailand scheduled push
# 1) CHECK Document/{today}_News/ — if Claude created it, push only (no re-combine)
# 2) If missing, WAIT for Articles/Facebook then CREATE once via create-news-json.py
# 3) PUSH via PUSH.bat (today only)
param(
    [switch]$Retry
)

$ErrorActionPreference = "Continue"
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Repo

$Parent = Split-Path -Parent $Repo
$LogDir = Join-Path $Parent "Logs"
if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$Today = Get-Date -Format "yyyy-MM-dd"
$Log = Join-Path $LogDir ("gov-daily-{0}.log" -f $Today)
$DocNewsDir = Join-Path $Parent ("Document\{0}_News" -f $Today)
$DocNews = Join-Path $DocNewsDir ("{0}_news.json" -f $Today)
$DataNews = Join-Path $Repo ("data\{0}_news.json" -f $Today)
$Briefing = Join-Path $Parent ("Document\{0}_Facebook\{0}_facebook_briefing.json" -f $Today)
$Creator = Join-Path $Repo "create-news-json.py"
$PushBat = Join-Path $Repo "PUSH.bat"
$WaitAttempts = if ($Retry) { 40 } else { 20 }
$WaitSeconds = 30

function Write-Log([string]$Message) {
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    Add-Content -LiteralPath $Log -Value $line -Encoding UTF8
}

function Get-ArticleCount {
    $articlesRoot = Join-Path $Parent "News\Articles"
    if (-not (Test-Path -LiteralPath $articlesRoot)) { return 0 }
    $needle1 = "\{0}\" -f $Today
    $needle2 = "/{0}/" -f $Today
    return @(Get-ChildItem -LiteralPath $articlesRoot -Recurse -Filter "article.json" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName.Contains($needle1) -or $_.FullName.Contains($needle2) }).Count
}

function Test-HasSources {
    param([int]$ArticleCount)
    return (Test-Path -LiteralPath $Briefing) -or ($ArticleCount -gt 0)
}

function Invoke-CreateIfMissing {
    Write-Log "  Running create-news-json.py (create Document/{today}_News/ only when missing)"
    & python $Creator --date $Today 2>&1 | ForEach-Object { Write-Log ("  {0}" -f $_) }
    return ($LASTEXITCODE -eq 0)
}

# Task Scheduler PATH / proxy hygiene
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

Write-Log ("=== Gov-News DailyPush.ps1 START (Retry={0}) ===" -f [bool]$Retry)
Write-Log ("Repo={0} Today={1}" -f $Repo, $Today)

if (-not (Test-Path -LiteralPath $PushBat)) {
    Write-Log ("ERROR: missing {0}" -f $PushBat)
    Write-Log "RESULT=FAIL"
    exit 1
}

# --- STEP 1: CHECK Document/{today}_News/ ---
Write-Log "[1/4] CHECK Document/{today}_News/"
$hasDoc = Test-Path -LiteralPath $DocNews
$hasData = Test-Path -LiteralPath $DataNews
$articleCount = Get-ArticleCount
$hasBrief = Test-Path -LiteralPath $Briefing
$hasSources = Test-HasSources -ArticleCount $articleCount

Write-Log ("  Document/{0}_News/ JSON exists={1}" -f $Today, $hasDoc)
Write-Log ("  data/{0}_news.json exists={1}" -f $Today, $hasData)
Write-Log ("  Articles={0} Facebook briefing={1}" -f $articleCount, $hasBrief)

if ($hasDoc) {
    Write-Log "[2/4] CREATE skipped — Document/{today}_News/ already exists (Claude), push only"
} else {
    # --- STEP 2: WAIT then CREATE when missing ---
    Write-Log "[2/4] Document/{today}_News/ missing — wait for sources then create"
    if (-not $hasSources) {
        Write-Log ("  WAIT up to {0}x{1}s for Articles/Facebook" -f $WaitAttempts, $WaitSeconds)
        for ($i = 1; $i -le $WaitAttempts; $i++) {
            Start-Sleep -Seconds $WaitSeconds
            $hasDoc = Test-Path -LiteralPath $DocNews
            if ($hasDoc) {
                Write-Log ("  wait {0}/{1}: Claude created Document/{2}_News/" -f $i, $WaitAttempts, $Today)
                break
            }
            $articleCount = Get-ArticleCount
            $hasBrief = Test-Path -LiteralPath $Briefing
            $hasSources = Test-HasSources -ArticleCount $articleCount
            Write-Log ("  wait {0}/{1}: articles={2} briefing={3}" -f $i, $WaitAttempts, $articleCount, $hasBrief)
            if ($hasSources) { break }
        }
    }

    $hasDoc = Test-Path -LiteralPath $DocNews
    if (-not $hasDoc) {
        if (-not $hasSources) {
            Write-Log ("ERROR: no Document/{0}_News/ and no Articles/Facebook after wait" -f $Today)
            Write-Log "RESULT=FAIL"
            exit 1
        }
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
        if (-not (Invoke-CreateIfMissing)) {
            Write-Log ("ERROR: create-news-json.py failed exit={0}" -f $LASTEXITCODE)
            Write-Log "RESULT=FAIL"
            exit 1
        }
        $hasDoc = Test-Path -LiteralPath $DocNews
        $hasData = Test-Path -LiteralPath $DataNews
    }
}

if (-not $hasDoc -and -not $hasData) {
    Write-Log "ERROR: today news JSON still missing"
    Write-Log "RESULT=FAIL"
    exit 1
}

try {
    $newsPath = if (Test-Path -LiteralPath $DocNews) { $DocNews } elseif (Test-Path -LiteralPath $DataNews) { $DataNews } else { $DocNews }
    $payload = Get-Content -LiteralPath $newsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $n = @($payload.posts).Count
    Write-Log ("  Ready posts={0} date={1}" -f $n, $payload.date)
    if ($n -lt 1) {
        Write-Log "ERROR: news has 0 posts"
        Write-Log "RESULT=FAIL"
        exit 1
    }
    if ($payload.date -ne $Today) {
        Write-Log ("ERROR: payload.date={0} is not TODAY={1}" -f $payload.date, $Today)
        Write-Log "RESULT=FAIL"
        exit 1
    }
} catch {
    Write-Log ("ERROR: cannot parse JSON: {0}" -f $_)
    Write-Log "RESULT=FAIL"
    exit 1
}

# --- STEP 3: PUSH ---
Write-Log "[3/4] PUSH via PUSH.bat"
$p = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", "`"$PushBat`"") -WorkingDirectory $Repo -Wait -PassThru -NoNewWindow
Write-Log ("  PUSH.bat exit={0}" -f $p.ExitCode)
if ($p.ExitCode -ne 0) {
    Write-Log "ERROR: PUSH.bat failed"
    Write-Log "RESULT=FAIL"
    exit $p.ExitCode
}

# --- STEP 4: VERIFY ---
Write-Log "[4/4] VERIFY git ahead=0"
Set-Location -LiteralPath $Repo
git fetch origin 2>$null | Out-Null
$ahead = 0
try { $ahead = [int](git rev-list --count "origin/master..HEAD" 2>$null) } catch { $ahead = -1 }
$head = (git rev-parse --short HEAD)
Write-Log ("  HEAD={0} AHEAD={1}" -f $head, $ahead)

if ($ahead -ne 0) {
    Write-Log ("ERROR: still ahead by {0}" -f $ahead)
    Write-Log "RESULT=FAIL"
    exit 1
}

Write-Log "RESULT=PASS"
Write-Log "SUCCESS https://chiraleo2000.github.io/gov-news-thailand/"
Write-Log "=== Gov-News DailyPush.ps1 END ==="
exit 0
