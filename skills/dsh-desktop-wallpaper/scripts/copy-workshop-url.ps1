<#
.SYNOPSIS
  Resolve a canonical Steam Workshop link for a wallpaper and put it on the clipboard.

.DESCRIPTION
  Uses the Steam WebAPI (ISteamRemoteStorage/GetPublishedFileDetails), which works even
  when steamcommunity.com itself is unreachable. Prints the title/tags/preview too, so a
  user can confirm they picked the right item before handing the link to an agent.

.PARAMETER PublishedFileId
  Workshop item id (the number in .../sharedfiles/filedetails/?id=<id>).

.PARAMETER Url
  Alternatively paste a workshop URL and let the script extract the id.

.PARAMETER NoClipboard
  Print only; do not touch the clipboard.
#>
param(
  [string]$PublishedFileId = '',
  [string]$Url = '',
  [switch]$NoClipboard
)
$ErrorActionPreference = 'Stop'

if (-not $PublishedFileId -and $Url) {
  $m = [regex]::Match($Url, '(?:\?|&)id=(\d+)|CommunityFilePage/(\d+)')
  if ($m.Success) { $PublishedFileId = ($m.Groups[1].Value + $m.Groups[2].Value) }
}
if (-not $PublishedFileId) { Write-Host 'ERROR: pass -PublishedFileId <id> or -Url <workshop url>'; exit 3 }

$link = 'https://steamcommunity.com/sharedfiles/filedetails/?id=' + $PublishedFileId
try {
  $body = "itemcount=1&publishedfileids[0]=$PublishedFileId"
  $resp = Invoke-RestMethod -Method Post -TimeoutSec 20 `
    -Uri 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' -Body $body
  $d = $resp.response.publishedfiledetails[0]
  Write-Host ('title  : ' + $d.title)
  Write-Host ('tags   : ' + (($d.tags | ForEach-Object { $_.tag }) -join ', '))
  Write-Host ('preview: ' + $d.preview_url)
} catch {
  Write-Host ('metadata lookup failed (link still usable): ' + $_.Exception.Message) -ForegroundColor Yellow
}

Write-Host ''
Write-Host ('workshop link: ' + $link) -ForegroundColor Green
if (-not $NoClipboard) {
  try { Set-Clipboard -Value $link; Write-Host 'copied to clipboard - paste it to your agent.' -ForegroundColor Green }
  catch { Write-Host 'could not access the clipboard; copy the line above manually.' -ForegroundColor Yellow }
}