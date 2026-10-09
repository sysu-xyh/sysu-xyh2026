<#
.SYNOPSIS
  Record a sanitised field note into the skill repository and commit it LOCALLY.

.DESCRIPTION
  For an agent that hit a problem this skill did not document and solved it:
  it writes reference/field-notes/YYYY-MM-DD-<slug>.md, stages it, and makes a local commit.

  THIS SCRIPT NEVER PUSHES. Publishing to the public repository is a human decision;
  a commit can be amended or dropped, a pushed commit cannot be unpublished.

  Before writing anything it scans the note for personal paths, credentials, private
  network addresses and machine identifiers, and refuses to continue if it finds any.
  Use -Preview to print the note without touching the filesystem or git.

.PARAMETER Title
  One-line title.

.PARAMETER Symptom
  What was observed (phenomenon only, no guesses).

.PARAMETER Cause
  Verified root cause.

.PARAMETER Fix
  What resolved it (exact keys / code where relevant).

.PARAMETER Verification
  How the fix was proven (command + expected result).

.PARAMETER Scope
  Optional: when it applies and when it does not.

.PARAMETER Repro
  Optional: minimal reproduction steps, one per line or ';' separated.

.PARAMETER Tag
  Optional tags, comma separated.

.PARAMETER Verified
  true (default) only if you actually proved the fix.

.PARAMETER Skill
  Which skill the note belongs to. Default: the folder name.

.PARAMETER Preview
  Print the note and run the safety scan; change nothing.

.PARAMETER NoCommit
  Write the file but skip git.
#>
param(
  [Parameter(Mandatory=$true)][string]$Title,
  [Parameter(Mandatory=$true)][string]$Symptom,
  [Parameter(Mandatory=$true)][string]$Cause,
  [Parameter(Mandatory=$true)][string]$Fix,
  [Parameter(Mandatory=$true)][string]$Verification,
  [string]$Scope = '',
  [string]$Repro = '',
  [string]$Tag = '',
  [ValidateSet('true','false')][string]$Verified = 'true',
  [string]$Skill = '',
  [switch]$Preview,
  [switch]$NoCommit
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillRoot = Split-Path -Parent $here
if (-not $Skill) { $Skill = Split-Path -Leaf $skillRoot }
$notesDir = Join-Path $skillRoot 'reference\field-notes'

# ---- reject machine-specific / secret content BEFORE writing anything -------------
$body = @"
## 症状（Symptom）

$Symptom

## 复现（Repro）

$Repro

## 根因（Cause）

$Cause

## 解法（Fix）

$Fix

## 验证（Verification）

$Verification

## 影响与适用边界（Scope）

$Scope
"@

$patterns = @(
  @{ n = 'personal Windows path'; r = '[A-Za-z]:\\Users\\[^\\\s]+' },
  @{ n = 'personal POSIX path';   r = '/home/[^/\s]+' },
  @{ n = 'credential (ghp_)';     r = 'ghp_[A-Za-z0-9]+' },
  @{ n = 'credential (gh pat)';   r = 'github_pat_[A-Za-z0-9_]+' },
  @{ n = 'credential (sk-)';      r = 'sk-[A-Za-z0-9]{8,}' },
  @{ n = 'bearer token';          r = '(?i)bearer\s+[A-Za-z0-9._-]{10,}' },
  @{ n = 'token/password kv';     r = '(?i)(token|password|secret|apikey|api_key)\s*[:=]\s*\S{6,}' },
  @{ n = 'private key block';     r = '-----BEGIN[A-Z ]*PRIVATE KEY-----' },
  @{ n = 'private network ip';    r = '\b(10\.[0-9]{1,3}|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' },
  @{ n = 'mDNS name';             r = '\.local\b' },
  @{ n = 'machine SID';           r = 'S-1-5-(21|32|33)-\d+' },
  @{ n = 'GUID-like machine id';  r = '\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b' }
)
$hits = @()
foreach ($p in $patterns) { if ($body -match $p.r) { $hits += $p.n } }
if ($hits.Count) {
  Write-Host 'REFUSED: the note contains content that must not become public:' -ForegroundColor Red
  $hits | Select-Object -Unique | ForEach-Object { Write-Host ("  - " + $_) -ForegroundColor Red }
  Write-Host 'Rewrite it with type-level wording (e.g. "a non-ASCII install path", "the default profile")'
  Write-Host 'and re-run. Nothing was written and nothing was committed.'
  exit 2
}

# ---- build the note -------------------------------------------------------------
$slug = ($Title.ToLower() -replace '[^a-z0-9]+','-').Trim('-')
if ($slug.Length -gt 60) { $slug = $slug.Substring(0,60).Trim('-') }
if (-not $slug) { $slug = 'note' }
$date = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
$fileName = "$date-$slug.md"
$target = Join-Path $notesDir $fileName

$tagList = ($Tag -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique) -join ', '
$dshVersion = if ($env:DSH_VERSION) { $env:DSH_VERSION } else { 'unknown' }

$reproBlock = if ($Repro) {
  (($Repro -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object -Begin { $i = 1 } -Process { "$i. $_"; $i++ }) -join "`n"
} else { '_未记录 / not recorded_' }

$note = @"
---
title: $Title
date: $date
skill: $Skill
verified: $Verified
environment: $([System.Environment]::OSVersion.VersionString)
dsh: $dshVersion
tags: [$tagList]
---

## 症状（Symptom）

$Symptom

## 复现（Repro）

$reproBlock

## 根因（Cause）

$Cause

## 解法（Fix）

$Fix

## 验证（Verification）

$Verification

## 影响与适用边界（Scope）

$Scope
"@

Write-Host ("note   : " + $target)
Write-Host ("length : " + $note.Length + " chars")
if ($Preview) {
  Write-Host '--- preview (nothing written) ---'
  Write-Host $note
  exit 0
}

New-Item -ItemType Directory -Force -Path $notesDir | Out-Null
if (Test-Path $target) {
  Write-Host 'REFUSED: that note already exists; choose a different title.' -ForegroundColor Red
  exit 3
}
[System.IO.File]::WriteAllText($target, $note, (New-Object System.Text.UTF8Encoding $false))
Write-Host 'written.'

if ($NoCommit) { Write-Host '-NoCommit given: not touching git.'; exit 0 }

# ---- local commit only (never push) ---------------------------------------------
$repo = (git -C $skillRoot rev-parse --show-toplevel 2>$null)
if (-not $repo) {
  Write-Host 'not inside a git working tree: the note is written but not committed.'
  exit 0
}

# refuse to commit media anywhere in the repo
$media = Get-ChildItem $repo -Recurse -File -Include *.mp4,*.webm,*.jpg,*.jpeg,*.png,*.webp,*.gif -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notlike '*\.git\*' }
if ($media) {
  Write-Host 'REFUSED: media files are present in the working tree; remove them before committing:' -ForegroundColor Red
  $media | ForEach-Object { Write-Host ('  ' + $_.FullName) }
  exit 4
}

if (-not (git -C $repo config user.email)) { git -C $repo config user.email 'agent@localhost' | Out-Null }
if (-not (git -C $repo config user.name))  { git -C $repo config user.name  'field-note agent' | Out-Null }

git -C $repo add -- $target | Out-Null
$msg = "field-notes: $Title`n`nSymptom: $Symptom`nCause: $Cause`nFix: $Fix`nVerification: $Verification`n`n[agent-field-note] verified=$Verified machine=windows dsh=$dshVersion skill=$Skill"
git -C $repo commit -q -m $msg
if ($LASTEXITCODE -ne 0) { Write-Host 'commit failed (nothing else was changed).' -ForegroundColor Red; exit 5 }

Write-Host 'committed locally (NOT pushed).'
Write-Host ('  repo : ' + $repo)
Write-Host ('  head : ' + (git -C $repo rev-parse --short HEAD))
Write-Host ''
Write-Host 'Publishing is a human decision: the owner reviews and pushes'
Write-Host '(e.g. GitHub Desktop -> Push origin), or drops the commit with:'
Write-Host ('  git -C "' + $repo + '" reset --soft HEAD~1')