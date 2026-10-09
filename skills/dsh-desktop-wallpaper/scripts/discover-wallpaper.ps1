<#
.SYNOPSIS
  Locate a Steam Workshop wallpaper on this machine and prepare its media for the plugin.

.DESCRIPTION
  Wallpaper Engine wallpapers (Steam AppID 431960) are downloaded by Steam into
    <SteamLibrary>\steamapps\workshop\content\431960\<publishedFileId>\
  This script finds every Steam library on the machine, locates the item, lists what it
  contains, and (optionally) copies the media into a fixed local assets folder.

  It never downloads anything and never touches the network unless -Metadata is given:
  the user subscribes in Steam, Steam does the downloading.

.PARAMETER PublishedFileId
  The workshop item id, from the page URL .../sharedfiles/filedetails/?id=<id>

.PARAMETER AppId
  Workshop app id. Default 431960 (Wallpaper Engine).

.PARAMETER CopyTo
  Optional fixed local folder. If the item contains a video, it is copied there as
  wallpaper.mp4 (plus a poster image if one exists).

.PARAMETER Metadata
  Also query the Steam WebAPI for title/tags/preview_url. Works even when
  steamcommunity.com is unreachable.

.PARAMETER StartVideoServer
  After copying, print the exact command + client.js values to use.
#>
param(
  [Parameter(Mandatory=$false)][string]$PublishedFileId,
  [string]$Url = '',
  [string]$AppId = '431960',
  [string]$CopyTo = '',
  [switch]$Metadata,
  [switch]$StartVideoServer
)

$ErrorActionPreference = 'Continue'
function Line($m) { Write-Host $m }

# accept a pasted workshop URL: ...?id=123 / ...&id=123 / steam://url/CommunityFilePage/123
if (-not $PublishedFileId -and $Url) {
  $m = [regex]::Match($Url, '(?:\?|&)id=(\d+)|CommunityFilePage/(\d+)')
  if ($m.Success) { $PublishedFileId = ($m.Groups[1].Value + $m.Groups[2].Value) }
}
if (-not $PublishedFileId) { Write-Host 'ERROR: pass -PublishedFileId <id> or -Url <workshop url>'; exit 3 }
Line ('target id: ' + $PublishedFileId)

Line "=== 1) Steam libraries ==="
$steamRoots = @()
foreach ($k in @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam','HKCU:\SOFTWARE\Valve\Steam')) {
  try {
    $p = (Get-ItemProperty -Path $k -ErrorAction Stop).InstallPath
    if ($p) { $steamRoots += $p }
  } catch {}
}
# fallback candidates when the registry has no InstallPath: the usual Steam folder names
# on every currently mounted drive (covers D:\Steam, E:\Games\Steam, ... without listing
# any machine-specific path). The registry value above always wins when present.
foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
  foreach ($name in @('Steam', 'SteamLibrary', 'Games\Steam')) {
    $cand = Join-Path ($drive.Root) $name
    if (Test-Path $cand) { $steamRoots += $cand }
  }
}
$steamRoots = $steamRoots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
foreach ($r in $steamRoots) { Line ("  steam: " + $r) }

$libraries = @()
foreach ($r in $steamRoots) {
  $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
  if (Test-Path $vdf) {
    $text = Get-Content $vdf -Raw
    foreach ($m in [regex]::Matches($text, '"path"\s*"([^"]+)"')) {
      $lib = $m.Groups[1].Value -replace '\\\\','\'
      if (Test-Path $lib) { $libraries += $lib }
    }
  }
  $libraries += $r
}
$libraries = $libraries | Select-Object -Unique
Line "  libraries found: $($libraries.Count)"
foreach ($l in $libraries) { Line ("    " + $l) }

Line ""
Line "=== 2) looking for workshop item $PublishedFileId (app $AppId) ==="
$hit = $null
foreach ($l in $libraries) {
  $cand = Join-Path $l "steamapps\workshop\content\$AppId\$PublishedFileId"
  if (Test-Path $cand) { $hit = $cand; break }
}
if (-not $hit) {
  Line "  NOT FOUND locally."
  Line ""
  Line "  Ask the user to do this in the Steam client (do NOT send them to third-party download sites):"
  Line "    1) install/open Steam and search for Wallpaper Engine (app $AppId)"
  Line "    2) open the workshop page of id $PublishedFileId and click 订阅 (Subscribe)"
  Line "    3) wait for Steam's Downloads page to finish"
  Line "    4) re-run this script"
  Line ""
  Line "  Also possible: the item is not a Wallpaper Engine wallpaper (different app id),"
  Line "  or the user is only browsing without subscribing."
  exit 2
}
Line "  FOUND: $hit"

Line ""
Line "=== 3) contents ==="
$files = Get-ChildItem $hit -Recurse -File -ErrorAction SilentlyContinue
foreach ($f in $files) { Line ("  {0,10}  {1}" -f $f.Length, $f.FullName.Substring($hit.Length + 1)) }

$videos = $files | Where-Object { $_.Extension -match '^\.(mp4|webm|mkv|mov)$' }
$images = $files | Where-Object { $_.Extension -match '^\.(jpg|jpeg|png|webp|gif)$' }
$scene  = $files | Where-Object { $_.Name -eq 'scene.pkg' }

Line ""
Line "=== 4) verdict ==="
if ($videos) {
  $v = $videos | Sort-Object Length -Descending | Select-Object -First 1
  Line ("  VIDEO wallpaper: " + $v.Name + "  (" + [math]::Round($v.Length/1MB,2) + " MB)")
} elseif ($scene) {
  Line "  SCENE wallpaper (scene.pkg): its content is not a plain video, so it cannot be"
  Line "  used as a video background directly. Use the preview image as a static background,"
  Line "  or ask the user to pick a video-type wallpaper instead."
} elseif ($images) {
  Line "  IMAGE-only wallpaper: use the largest image as a static background."
} else {
  Line "  No usable media found inside the item."
}

if ($CopyTo -and ($videos -or $images)) {
  Line ""
  Line "=== 5) copying media to $CopyTo ==="
  New-Item -ItemType Directory -Force -Path $CopyTo | Out-Null
  if ($videos) {
    $v = $videos | Sort-Object Length -Descending | Select-Object -First 1
    Copy-Item $v.FullName (Join-Path $CopyTo 'wallpaper.mp4') -Force
    Line ("  copied video -> " + (Join-Path $CopyTo 'wallpaper.mp4'))
  }
  if ($images) {
    $img = $images | Sort-Object Length -Descending | Select-Object -First 1
    Copy-Item $img.FullName (Join-Path $CopyTo ('poster' + $img.Extension)) -Force
    Line ("  copied poster -> " + (Join-Path $CopyTo ('poster' + $img.Extension)))
  }
}

if ($Metadata) {
  Line ""
  Line "=== 6) Steam WebAPI metadata (no steamcommunity.com needed) ==="
  try {
    $body = "itemcount=1&publishedfileids[0]=$PublishedFileId"
    $resp = Invoke-RestMethod -Method Post -TimeoutSec 20 `
      -Uri 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' -Body $body
    $d = $resp.response.publishedfiledetails[0]
    Line ("  title      : " + $d.title)
    Line ("  tags       : " + (($d.tags | ForEach-Object { $_.tag }) -join ', '))
    Line ("  preview    : " + $d.preview_url)
    Line ("  bigger prev: " + $d.preview_url + '?imw=3840&imh=2160&ima=fit&impolicy=Letterbox')
    Line ("  file size  : " + $d.file_size)
  } catch {
    Line ("  metadata query failed: " + $_.Exception.Message)
  }
}

Line ""
Line "=== next steps for the agent ==="
if ($videos) {
  Line "  1) keep the video in a FIXED LOCAL folder (never a removable drive)"
  Line "  2) start the local video server:  optional\video-server\start-wallpaper.bat"
  Line "     (silent variant for a logon task: start-video-server-silent.vbs)"
  Line "  3) in template\plugin\client.js set:"
  Line "       var VIDEO_URL  = 'http://127.0.0.1:8787/wallpaper.mp4';"
  Line "       var POSTER_URL = 'http://127.0.0.1:8787/wallpaper.webp';"
  Line "  4) install the plugin (scripts\install-plugin.ps1) and restart the Harness normally"
} else {
  Line "  1) put the image in a fixed local folder"
  Line "  2) set it as LAYER_CSS background-image in template\plugin\client.js (data URL or local URL)"
  Line "  3) install the plugin and restart the Harness normally"
}