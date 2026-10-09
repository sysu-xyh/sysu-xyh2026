<#
.SYNOPSIS
  One-command setup: make this skill discoverable, install the wallpaper plugin, and
  register a silent logon task that keeps the wallpaper video server running.

.DESCRIPTION
  Intended to be run right after cloning the repository, e.g.

    git clone https://github.com/sysu-xyh/sysu-xyh2026.git $env:TEMP\sysu-repo
    powershell -NoProfile -ExecutionPolicy Bypass -File `
      $env:TEMP\sysu-repo\skills\dsh-desktop-wallpaper\scripts\bootstrap.ps1

  What it does:
    1. links this skill into <dshHome>\skills\<skillName> so the Harness discovers it
       (skill discovery only looks ONE level below a skill root)
    2. copies the plugin to a fixed LOCAL directory and installs it into the profile
       (dependency + bundles + junction + lock, then verifies the import)
    3. starts the video server and registers a silent logon task for it

  What it deliberately does NOT do:
    - download any wallpaper (the user subscribes in Steam; see reference/getting-the-wallpaper.md)
    - restart the Harness (that would kill the session running this script)

.PARAMETER SkillDir
  The skill directory holding SKILL.md. Defaults to the parent of this script.

.PARAMETER DshHome
  Harness home. Defaults to $env:DSH_HOME, else $env:USERPROFILE\.dsh

.PARAMETER InstallDir
  Fixed LOCAL directory the plugin runs from. Default: <LocalAppData>\dsh-wallpaper\plugin

.PARAMETER ProfileName
  DSH profile to install into. Default: desktop

.PARAMETER NoSkillLink
  Do not link the skill into the skill root.

.PARAMETER NoVideoTask
  Do not register the logon task for the video server.

.PARAMETER TaskName
  Logon task name. Default: DSH Wallpaper Video Server
#>
param(
  [string]$SkillDir = '',
  [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }),
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'dsh-wallpaper\plugin'),
  [string]$ProfileName = 'desktop',
  [switch]$NoSkillLink,
  [switch]$NoVideoTask,
  [string]$TaskName = 'DSH Wallpaper Video Server'
)

$ErrorActionPreference = 'Stop'
function Step($m) { Write-Host ''; Write-Host ('== ' + $m) -ForegroundColor Cyan }
function Ok($m)   { Write-Host ('   ' + $m) -ForegroundColor Green }
function Warn($m) { Write-Host ('   ' + $m) -ForegroundColor Yellow }

if (-not $SkillDir) { $SkillDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$SkillDir = (Resolve-Path $SkillDir).Path
if (-not (Test-Path (Join-Path $SkillDir 'SKILL.md'))) { throw "SKILL.md not found in $SkillDir" }
$skillName = Split-Path -Leaf $SkillDir
Write-Host ('bootstrap: skill=' + $skillName + '  dshHome=' + $DshHome)

# ---------------------------------------------------------------- 1) skill discovery
Step '1/4  make the skill discoverable'
if ($NoSkillLink) {
  Warn '-NoSkillLink given: skipped'
} else {
  $skillRoot = Join-Path $DshHome 'skills'
  New-Item -ItemType Directory -Force -Path $skillRoot | Out-Null
  $skillLink = Join-Path $skillRoot $skillName
  if (Test-Path $skillLink) {
    $existing = Get-Item $skillLink -Force
    if ($existing.LinkType -and (($existing.Target -join ',') -eq $SkillDir)) {
      Ok "already linked: $skillLink"
    } else {
      Warn "replacing existing entry: $skillLink"
      if ($existing.LinkType) { $existing.Delete() } else { Remove-Item $skillLink -Recurse -Force }
      New-Item -ItemType Junction -Path $skillLink -Target $SkillDir | Out-Null
      Ok "linked: $skillLink  ->  $SkillDir"
    }
  } else {
    New-Item -ItemType Junction -Path $skillLink -Target $SkillDir | Out-Null
    Ok "linked: $skillLink  ->  $SkillDir"
  }
  Warn 'the skill catalog refreshes on the next model step (no restart needed)'
}

# ---------------------------------------------------------------- 2) plugin install
Step '2/4  install the wallpaper plugin'
$installer = Join-Path $SkillDir 'scripts\install-plugin.ps1'
$pluginDir = Join-Path $SkillDir 'template\plugin'
if (-not (Test-Path $installer)) { throw "missing $installer" }
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer -PluginDir $pluginDir -InstallDir $InstallDir -ProfileName $ProfileName -DshHome $DshHome
if ($LASTEXITCODE -ne 0) { throw "plugin install failed (exit $LASTEXITCODE)" }
Ok 'plugin installed and the import was verified'

# ---------------------------------------------------------------- 3) video server
Step '3/4  video server'
$assets = Join-Path (Split-Path -Parent $InstallDir) 'assets'
New-Item -ItemType Directory -Force -Path $assets | Out-Null
$serverScript = Join-Path $SkillDir 'optional\video-server\wallpaper-server.mjs'
$vbsWrapper   = Join-Path $SkillDir 'optional\video-server\start-video-server-silent.vbs'
$nodeExe = 'C:\Program Files\nodejs\node.exe'
if (-not (Test-Path $nodeExe)) { $nodeExe = 'node' }
Ok ('video: put your wallpaper video at ' + (Join-Path $assets 'wallpaper.mp4'))
Warn ('the bundled service reads the video path configured inside wallpaper-server.mjs')
Warn ('start it manually any time: ' + $serverScript)

$serverUp = $false
try {
  $c = New-Object System.Net.Sockets.TcpClient
  $iar = $c.BeginConnect('127.0.0.1', 8787, $null, $null)
  $serverUp = $iar.AsyncWaitHandle.WaitOne(500)
  $c.Close()
} catch { $serverUp = $false }
if (-not $serverUp) {
  Start-Process -FilePath $nodeExe -ArgumentList ('"' + $serverScript + '"') -WindowStyle Hidden
  Start-Sleep -Seconds 2
  Ok 'video server started now'
} else {
  Ok 'video server already running on 8787'
}

# ---------------------------------------------------------------- 4) logon task
Step '4/4  keep the video server running at logon'
if ($NoVideoTask) {
  Warn '-NoVideoTask given: skipped'
} else {
  $act = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"' + $vbsWrapper + '"')
  $trg = New-ScheduledTaskTrigger -AtLogOn -User ($env:USERDOMAIN + '\' + $env:USERNAME)
  $trg.Delay = 'PT15S'
  $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
  $prn = New-ScheduledTaskPrincipal -UserId ($env:USERDOMAIN + '\' + $env:USERNAME) -LogonType Interactive -RunLevel Limited
  Register-ScheduledTask -TaskName $TaskName -Action $act -Trigger $trg -Settings $set -Principal $prn -Force -Description 'Starts the local wallpaper video server silently at logon.' | Out-Null
  Ok ('registered logon task: ' + $TaskName)
}
Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' NEXT STEPS (a human must do these two)' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' 1) subscribe to the wallpaper in Steam, so its files land locally:'
Write-Host '      see reference/getting-the-wallpaper.md (copy the workshop URL to the agent)'
Write-Host ' 2) restart DeepSeek Harness normally (no special launcher, no debug port)'
Write-Host '    the wallpaper should appear, with a pill bottom-left to toggle it'
Write-Host ''