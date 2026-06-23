# SETUP: Store GitHub PAT securely for automated deployments
# Run this ONCE to configure the PAT for future automated runs
# The PAT will be stored in Windows Credential Manager

# To use:
# 1. Set the PAT value below
# 2. Run this script
# 3. PAT will be stored securely and used by deploy-and-push.ps1

$GitHubPAT = "ghp_YOUR_TOKEN_HERE"

# Store PAT in environment variable (for current session)
[Environment]::SetEnvironmentVariable("GITHUB_PAT", $GitHubPAT, "User")

Write-Host "✅ GitHub PAT stored in Windows environment variables" -ForegroundColor Green
Write-Host "   Variable: GITHUB_PAT" -ForegroundColor Yellow
Write-Host "   Scope: User" -ForegroundColor Yellow
Write-Host ""
Write-Host "ℹ️  You can now run: deploy-and-push.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠️  SECURITY NOTE:" -ForegroundColor Yellow
Write-Host "   - The PAT is stored in Windows User environment variables" -ForegroundColor Yellow
Write-Host "   - Only your user account can access it" -ForegroundColor Yellow
Write-Host "   - For server automation, use Windows Credential Manager instead" -ForegroundColor Yellow
Write-Host ""

# Alternative: Store in Credential Manager (more secure)
# Uncomment below to use Credential Manager instead:

<#
$Credential = New-Object System.Management.Automation.PSCredential(
    "chiraleo2000",
    (ConvertTo-SecureString $GitHubPAT -AsPlainText -Force)
)

# Store in credential manager
$Credential | Export-Clixml -Path "$env:APPDATA\github-pat.cred"

Write-Host "✅ GitHub PAT stored securely in Credential Manager" -ForegroundColor Green
Write-Host "   Location: $env:APPDATA\github-pat.cred" -ForegroundColor Yellow
#>
