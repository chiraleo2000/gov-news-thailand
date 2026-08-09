# DailyPush.ps1 - scheduled 18:00 Gov-News Thailand
# 1) CHECK today news JSON
# 2) ALWAYS RECREATE/COMBINE from ALL Articles + Facebook briefing
# 3) PUSH via PUSH.bat
# Never republishes an older date.

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
$DocNews = Join-Path $Parent ("Document\{0}_News\{0}_news.json" -f $Today)
$DataNews = Join-Path $Repo ("data\{0}_news.json" -f $Today)
$Briefing = Join-Path $Parent ("Document\{0}_Facebook\{0}_facebook_briefing.json" -f $Today)
$Creator = Join-Path $Repo "create-news-json.py"
$PushBat = Join-Path $Repo "PUSH.bat"

function Write-Log([string]$Message) {
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    Add-Content -LiteralPath $Log -Value $line -Encoding UTF8
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

Write-Log "=== Gov-News DailyPush.ps1 START ==="
Write-Log ("Repo={0}" -f $Repo)
Write-Log ("Today={0}" -f $Today)

# --- STEP 1: CHECK ---
Write-Log "[1/4] CHECK today sources"
$hasDoc = Test-Path -LiteralPath $DocNews
$hasData = Test-Path -LiteralPath $DataNews
$hasBrief = Test-Path -LiteralPath $Briefing
$articleCount = 0
$articlesRoot = Join-Path $Parent "News\Articles"
if (Test-Path -LiteralPath $articlesRoot) {
    $needle1 = "\{0}\" -f $Today
    $needle2 = "/{0}/" -f $Today
    $articleCount = @(Get-ChildItem -LiteralPath $articlesRoot -Recurse -Filter "article.json" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName.Contains($needle1) -or $_.FullName.Contains($needle2) }).Count
}
Write-Log ("  Document news exists={0}" -f $hasDoc)
Write-Log ("  data news exists={0}" -f $hasData)
Write-Log ("  Facebook briefing exists={0}" -f $hasBrief)
Write-Log ("  Articles for {0} count={1}" -f $Today, $articleCount)

if ((-not $hasBrief) -and ($articleCount -eq 0) -and (-not $hasDoc) -and (-not $hasData)) {
    Write-Log ("ERROR: no Facebook briefing, no Articles, no existing news for {0}" -f $Today)
    Write-Log "RESULT=FAIL"
    exit 1
}

# --- STEP 2: RECREATE / COMBINE (always) ---
Write-Log "[2/4] RECREATE/COMBINE from ALL Articles + Facebook"
if (-not (Test-Path -LiteralPath $Creator)) {
    Write-Log ("ERROR: missing {0}" -f $Creator)
    Write-Log "RESULT=FAIL"
    exit 1
}

$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) {
    Write-Log "ERROR: python not on PATH"
    Write-Log "RESULT=FAIL"
    exit 1
}

& python $Creator $Today --force 2>&1 | ForEach-Object { Write-Log ("  {0}" -f $_) }
if ($LASTEXITCODE -ne 0) {
    Write-Log ("ERROR: create-news-json.py failed exit={0}" -f $LASTEXITCODE)
    Write-Log "RESULT=FAIL"
    exit 1
}

if ((-not (Test-Path -LiteralPath $DocNews)) -and (-not (Test-Path -LiteralPath $DataNews))) {
    Write-Log "ERROR: create finished but today news JSON still missing"
    Write-Log "RESULT=FAIL"
    exit 1
}

try {
    $newsPath = if (Test-Path -LiteralPath $DataNews) { $DataNews } else { $DocNews }
    $payload = Get-Content -LiteralPath $newsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $n = @($payload.posts).Count
    Write-Log ("  Combined posts={0} date={1}" -f $n, $payload.date)
    if ($n -lt 1) {
        Write-Log "ERROR: combined news has 0 posts"
        Write-Log "RESULT=FAIL"
        exit 1
    }
    if ($payload.date -ne $Today) {
        Write-Log ("ERROR: payload.date={0} is not TODAY={1}" -f $payload.date, $Today)
        Write-Log "RESULT=FAIL"
        exit 1
    }
} catch {
    Write-Log ("ERROR: cannot parse created JSON: {0}" -f $_)
    Write-Log "RESULT=FAIL"
    exit 1
}

# --- STEP 3: PUSH ---
Write-Log "[3/4] PUSH via PUSH.bat"
if (-not (Test-Path -LiteralPath $PushBat)) {
    Write-Log ("ERROR: missing {0}" -f $PushBat)
    Write-Log "RESULT=FAIL"
    exit 1
}

$p = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", "`"$PushBat`"") -WorkingDirectory $Repo -Wait -PassThru -NoNewWindow
Write-Log ("  PUSH.bat exit={0}" -f $p.ExitCode)
if ($p.ExitCode -ne 0) {
    Write-Log "ERROR: PUSH.bat failed"
    Write-Log "RESULT=FAIL"
    exit $p.ExitCode
}

# --- STEP 4: VERIFY ---
Write-Log "[4/4] VERIFY git ahead=0 and today file present"
Set-Location -LiteralPath $Repo
git fetch origin 2>$null | Out-Null
$ahead = 0
try { $ahead = [int](git rev-list --count "origin/master..HEAD" 2>$null) } catch { $ahead = -1 }
$head = (git rev-parse --short HEAD)
Write-Log ("  HEAD={0} AHEAD={1} data_exists={2}" -f $head, $ahead, (Test-Path -LiteralPath $DataNews))

if ($ahead -ne 0) {
    Write-Log ("ERROR: still ahead by {0}" -f $ahead)
    Write-Log "RESULT=FAIL"
    exit 1
}

Write-Log "RESULT=PASS"
Write-Log "SUCCESS https://chiraleo2000.github.io/gov-news-thailand/"
Write-Log "=== Gov-News DailyPush.ps1 END ==="
exit 0
