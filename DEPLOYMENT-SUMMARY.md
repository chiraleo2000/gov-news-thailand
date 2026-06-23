# 🚀 Gov News GitHub Pages Deployment - Complete Guide

**Status:** ✅ **DEPLOYED & LIVE**  
**Date:** 2026-06-20  
**Latest Commit:** `1c3fd08` - "Update 2026-06-20_news.json"  
**Site:** https://chiraleo2000.github.io/gov-news-thailand/

---

## ✅ What Was Deployed

| Item | Status | Details |
|------|--------|---------|
| **Daily News JSON** | ✅ Live | `2026-06-20_news.json` (30 KB) |
| **Manifest** | ✅ Updated | Latest entry at index 0 |
| **Git Commit** | ✅ Pushed | `1c3fd08` on `origin/master` |
| **GitHub Pages** | ✅ Published | Accessible within 5 minutes |

---

## 🔑 GitHub PAT Configuration

Your GitHub Personal Access Token (PAT) is now configured for automated deployments.

### Option 1: Environment Variable (Recommended for Current Session)

Already configured! The PAT is set as `GITHUB_PAT` environment variable.

```powershell
# Verify it's set:
$env:GITHUB_PAT
```

### Option 2: Persistent Setup (Survives Reboot)

Run this ONE time to store PAT permanently:

```powershell
# From PowerShell as Administrator:
[Environment]::SetEnvironmentVariable("GITHUB_PAT", "ghp_YOUR_TOKEN_HERE", "User")

# Or run:
.\deploy-env-example.ps1
```

---

## 📋 How to Deploy Daily News

### Quick Deploy (Automatic)

```bash
# From Command Prompt:
cd D:\Gov-News-GitHub\gov-news-thailand
run-deploy.cmd
```

### PowerShell Deploy (Full Control)

```powershell
# With environment variable:
.\deploy-and-push.ps1

# With explicit PAT:
.\deploy-and-push.ps1 -GitHubPAT "ghp_YOUR_TOKEN_HERE"

# With specific date:
.\deploy-and-push.ps1 -TargetDate "2026-06-21"
```

### Python Alternative (if you use Python automation)

```python
import subprocess
import os

# Set PAT in environment
os.environ['GITHUB_PAT'] = 'ghp_YOUR_TOKEN_HERE'

# Run PowerShell script
result = subprocess.run([
    'powershell',
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', 'D:\\Gov-News-GitHub\\gov-news-thailand\\deploy-and-push.ps1'
], env=os.environ, capture_output=True, text=True)

print(result.stdout)
if result.returncode != 0:
    print("ERROR:", result.stderr)
```

---

## 🔐 Security Notes

### PAT Best Practices

1. ✅ **Token is NOT hardcoded** in scripts
2. ✅ **Token uses environment variables** (protected in user profile)
3. ✅ **Token has limited scope** (personal access)
4. ✅ **Token can be revoked** easily from GitHub settings

### Token Scopes

Current PAT has access to:
- `repo` - Full control of private repositories
- ⚠️ **Do NOT** commit token to Git
- ⚠️ **Do NOT** share token in logs or emails

### If Token Compromises

If the token is leaked:

1. Go to: https://github.com/settings/tokens
2. Delete the compromised token
3. Generate a new token
4. Update `GITHUB_PAT` environment variable
5. Run deployment again

---

## 📊 Deployment Process

```
Step 1: Source Data
  Document/2026-06-20_News/2026-06-20_news.json

Step 2: Copy to GitHub Pages
  → gov-news-thailand/data/2026-06-20_news.json

Step 3: Update Manifest
  → data/manifest.json (add latest at index 0)

Step 4: Git Commit
  → Create commit with message "Deploy: 2026-06-20_news.json"

Step 5: Git Push
  → Push to https://github.com/chiraleo2000/gov-news-thailand.git
  → PAT authentication from GITHUB_PAT env variable

Step 6: GitHub Pages Build
  → Auto-publishes to https://chiraleo2000.github.io/gov-news-thailand/
  → Takes ~5 minutes to reflect changes
```

---

## 📝 Script Files

| File | Purpose | How to Use |
|------|---------|-----------|
| `deploy-and-push.ps1` | Main deployment automation | `.\deploy-and-push.ps1` |
| `deploy-env-example.ps1` | Setup PAT permanently | `.\deploy-env-example.ps1` |
| `run-deploy.cmd` | Quick Windows batch runner | `run-deploy.cmd` |
| `DEPLOYMENT-SUMMARY.md` | This file | Reference guide |

---

## 🔍 Verification

### Check Local Commit

```bash
git log --oneline -3
# Should show: 1c3fd08 Update 2026-06-20_news.json
```

### Check Remote

```bash
git log origin/master --oneline -3
# Should match local log
```

### Check GitHub Website

Visit: https://github.com/chiraleo2000/gov-news-thailand/commits/master
- Should see `1c3fd08 Update 2026-06-20_news.json` at the top

### Check Published Site

Visit: https://chiraleo2000.github.io/gov-news-thailand/
- Data should reflect latest news JSON
- Check browser console (F12) for any errors

---

## 🆘 Troubleshooting

### "GITHUB_PAT not found" Error

**Solution:**
1. Run `deploy-env-example.ps1` to set environment variable
2. Close and reopen PowerShell/Command Prompt
3. Verify: `echo %GITHUB_PAT%`

### "Authentication failed" Error

**Solution:**
1. Verify PAT is still valid: https://github.com/settings/tokens
2. Regenerate PAT if needed
3. Update `GITHUB_PAT` environment variable
4. Test with: `git ls-remote origin`

### "Files not found" Error

**Solution:**
1. Verify source JSON exists: `D:\Gov-News-GitHub\Document\{DATE}_News\{DATE}_news.json`
2. Check date is correct: `deploy-and-push.ps1 -TargetDate "2026-06-20"`
3. Verify data folder exists: `D:\Gov-News-GitHub\gov-news-thailand\data\`

### Git Lock Errors

**Solution:**
```bash
cd D:\Gov-News-GitHub\gov-news-thailand
rm .git/index.lock  # Or remove via Windows Explorer
git status
```

---

## 📞 Support

For issues:
1. Check Git log: `git log --oneline -10`
2. Check status: `git status`
3. View deployment log: Look for `.ps1` output
4. Verify remote: `git remote -v`

---

## ✨ Next Steps

1. ✅ Daily news deployed (2026-06-20)
2. ✅ PAT authentication configured
3. ✅ Deployment scripts ready
4. → Schedule automated daily runs (optional)
5. → Monitor GitHub Actions builds

---

**Last Updated:** 2026-06-20 14:08 UTC  
**Author:** Gov News Auto-Deploy System  
**Repository:** https://github.com/chiraleo2000/gov-news-thailand
