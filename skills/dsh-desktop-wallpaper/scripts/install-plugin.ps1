<#
.SYNOPSIS
  Install the DeepSeek Harness live-wallpaper client plugin into a DSH profile.

.DESCRIPTION
  Why a script: installing a local (link:) bundle into a DSH profile needs THREE places
  to agree, and a missed one produces the confusing failure "failed to import":
    1. profiles/<name>/package.json  -> dependencies link: + dsh.profile.bundles entry
    2. profiles/<name>/node_modules/@local/<pkg> -> junction to the local plugin dir
    3. profiles/<name>/pnpm-lock.yaml -> stale path must be updated if it points elsewhere
  This script does all three and then verifies by resolving the bare package specifier
  from the profile directory (no app restart needed).

.PARAMETER PluginDir
  Path to the plugin template (the folder containing package.json + client.js).

.PARAMETER InstallDir
  Fixed LOCAL directory the plugin will run from. Default: <LocalAppData>\dsh-wallpaper\plugin
  Never use a removable drive here.

.PARAMETER ProfileName
  DSH profile to install into. Default: desktop

.PARAMETER DshHome
  DSH home. Default: $env:DSH_HOME, else $env:USERPROFILE\.dsh
#>
param(
  [Parameter(Mandatory=$true)][string]$PluginDir,
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'dsh-wallpaper\plugin'),
  [string]$ProfileName = 'desktop',
  [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' })
)

$ErrorActionPreference = 'Stop'
$PluginDir = (Resolve-Path $PluginDir).Path
$profile = Join-Path $DshHome "profiles\$ProfileName"

if (-not (Test-Path (Join-Path $PluginDir 'package.json'))) { throw "no package.json in $PluginDir" }
if (-not (Test-Path $profile)) { throw "profile not found: $profile" }

$pkg = Get-Content (Join-Path $PluginDir 'package.json') -Raw | ConvertFrom-Json
$pkgName = $pkg.name
if (-not $pkgName) { throw "plugin package.json has no name" }
Write-Host "[1/5] plugin '$pkgName'  ->  $InstallDir"

# --- 1) copy the plugin to a fixed LOCAL directory -------------------------------
New-Item -ItemType Directory -Force -Path (Split-Path $InstallDir -Parent) | Out-Null
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item (Join-Path $PluginDir '*') $InstallDir -Recurse -Force
if (-not (Test-Path (Join-Path $InstallDir 'client.js'))) { throw "client.js missing after copy" }

# --- 2) profile package.json: dependency + bundles entry -------------------------
$pkgPath = Join-Path $profile 'package.json'
Copy-Item $pkgPath "$pkgPath.bak-wallpaper" -Force -ErrorAction SilentlyContinue
$prof = Get-Content $pkgPath -Raw | ConvertFrom-Json
$linkSpec = 'link:' + ($InstallDir -replace '\\','/')

if (-not $prof.dependencies) { $prof | Add-Member -NotePropertyName dependencies -NotePropertyValue ([pscustomobject]@{}) -Force }
$prof.dependencies | Add-Member -NotePropertyName $pkgName -NotePropertyValue $linkSpec -Force

if (-not $prof.dsh) { $prof | Add-Member -NotePropertyName dsh -NotePropertyValue ([pscustomobject]@{}) -Force }
if (-not $prof.dsh.profile) { $prof.dsh | Add-Member -NotePropertyName profile -NotePropertyValue ([pscustomobject]@{}) -Force }
$bundles = @($prof.dsh.profile.bundles)
if ($bundles -notcontains $pkgName) { $bundles += $pkgName }
$prof.dsh.profile | Add-Member -NotePropertyName bundles -NotePropertyValue $bundles -Force

$prof | ConvertTo-Json -Depth 8 | Set-Content $pkgPath -Encoding UTF8
Write-Host "[2/5] wrote $pkgPath (dependency + bundles)"

# --- 3) node_modules junction ---------------------------------------------------
$scopeDir = Join-Path $profile 'node_modules\@local'
New-Item -ItemType Directory -Force -Path $scopeDir | Out-Null
$link = Join-Path $scopeDir ($pkgName -replace '^@[^/]+/','')
if (Test-Path $link) {
  $item = Get-Item $link -Force
  if ($item.LinkType) { $item.Delete() } else { Remove-Item $link -Recurse -Force }
}
New-Item -ItemType Junction -Path $link -Target $InstallDir | Out-Null
Write-Host "[3/5] junction $link -> $InstallDir"

# --- 4) refresh stale paths in pnpm-lock.yaml -----------------------------------
$lock = Join-Path $profile 'pnpm-lock.yaml'
if (Test-Path $lock) {
  $before = Get-Content $lock -Raw
  $after = [regex]::Replace($before, 'link:[A-Za-z]:/[^\s'']*' + [regex]::Escape((Split-Path $PluginDir -Leaf)) + '[^\s'']*', $linkSpec)
  if ($after -ne $before) { Copy-Item $lock "$lock.bak-wallpaper" -Force; Set-Content $lock $after -Encoding UTF8; Write-Host "[4/5] updated stale path(s) in pnpm-lock.yaml" }
  else { Write-Host "[4/5] pnpm-lock.yaml: nothing to update" }
} else { Write-Host "[4/5] no pnpm-lock.yaml (skipped)" }

# --- 5) verify by resolving the bare specifier FROM the profile dir -------------
Write-Host "[5/5] verifying import from $profile ..."
Push-Location $profile
try {
  $out = & node -e "import('$pkgName').then(m=>console.log('OK ' + Object.keys(m).join(','))).catch(e=>console.log('FAIL ' + (e.code||'') + ' ' + e.message))" 2>&1
} finally { Pop-Location }
Write-Host "      node says: $out"
if ("$out" -notmatch '^OK') {
  Write-Warning "verification failed - the plugin will NOT load (this is the 'failed to import' state)."
  Write-Warning "check: profile package.json dependency + junction target + that the plugin dir is on a fixed local disk."
  exit 1
}
Write-Host ""
Write-Host "DONE. Restart DeepSeek Harness NORMALLY (no special launcher, no debug port)."
Write-Host "A pill should appear bottom-left:  wallpaper ON - live <W>x<H> (click)"