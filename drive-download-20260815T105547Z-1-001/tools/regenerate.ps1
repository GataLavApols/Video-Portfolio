# ============================================================
#  Portfolio data generator
#  Scans videos/ and images/, merges your notes from
#  js/details.json, and writes js/data.js (used by the site).
#
#  When to run:
#    - After adding or removing videos/images
#    - After editing js/details.json
#
#  Run it:  right-click > Run with PowerShell  (or a terminal)
#  Tip: first run also creates js/details.json so you can give
#       each reel a real title, description, category and tags.
# ============================================================

$ErrorActionPreference = "Stop"

# --- Locate ffmpeg/ffprobe -------------------------------------------
function Find-FFprobe {
    $cmd = Get-Command ffprobe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $wingetRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    $candidates = @()
    if (Test-Path -LiteralPath $wingetRoot) {
        $candidates += Get-ChildItem -Path $wingetRoot -Recurse -Filter ffprobe.exe -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
    }
    foreach ($c in $candidates) { if ($c) { return $c } }
    throw "ffprobe not found. Install ffmpeg first:  winget install Gyan.FFmpeg"
}
$ffprobe = Find-FFprobe

# --- Folders -----------------------------------------------------------
$base     = Split-Path $PSScriptRoot -Parent
$videoDir = Join-Path $base "videos"
$imgDir   = Join-Path $base "images"
$jsDir    = Join-Path $base "js"
$detailsPath = Join-Path $jsDir "details.json"
$dataPath    = Join-Path $jsDir "data.js"
New-Item -ItemType Directory -Path $imgDir, $jsDir -Force | Out-Null

$entries = [System.Collections.Generic.List[object]]::new()

# --- Collect video files (prefer .mp4, dedupe by base name) -------------
$thumbDir = Join-Path $base "thumbs"
$videoExts = @(".mov", ".mp4", ".mkv", ".webm", ".m4v", ".avi")
$videos = @()
foreach ($g in (Get-ChildItem -LiteralPath $videoDir -File -ErrorAction SilentlyContinue |
    Where-Object { $videoExts -contains $_.Extension.ToLower() } |
    Group-Object { $_.BaseName })) {
    $mp4 = $g.Group | Where-Object { $_.Extension -eq ".mp4" } | Select-Object -First 1
    $src = if ($mp4) { $mp4 } else { $g.Group | Sort-Object Extension | Select-Object -First 1 }
    $thumbPath = Join-Path $thumbDir ($src.BaseName + ".jpg")
    $videos += [PSCustomObject]@{
        Base   = $g.Name
        Src    = "videos/$($src.Name)"
        Poster = if (Test-Path -LiteralPath $thumbPath) { "thumbs/$($src.BaseName).jpg" } else { "videos/$($src.Name)" }
        Path   = $src.FullName
        Type   = "video"
    }
}

# --- Collect images ------------------------------------------------------
$imgExts = @(".jpg", ".jpeg", ".png", ".webp", ".gif")
$images = @()
foreach ($f in (Get-ChildItem -LiteralPath $imgDir -File -ErrorAction SilentlyContinue |
    Where-Object { $imgExts -contains $_.Extension.ToLower() })) {
    $images += [PSCustomObject]@{
        Base   = $f.BaseName
        Src    = "images/$($f.Name)"
        Poster = "images/$($f.Name)"
        Path   = $f.FullName
        Type   = "image"
    }
}

# --- First run: create js/details.json template --------------------------
if (-not (Test-Path -LiteralPath $detailsPath)) {
    $template = @{
        "_note" = "Optional per-reel details. Key = file name without extension. Set order to rearrange (1,2,3...). Leave hide=true to remove from the site without deleting the file."
        "_example" = @{
            title = "My best reel"
            category = "Products"
            description = "A short description of what this video shows."
            tags = @("hook", "product", "launch")
            order = 1
        }
    }
    $idx = 0
    foreach ($v in ($videos + $images | Sort-Object Base)) {
        if (-not $template.ContainsKey($v.Base)) {
            $idx++
            $template[$v.Base] = @{
                title = if ($v.Type -eq "image") { "Photo {0:D2}" -f $idx } else { "Reel {0:D2}" -f $idx }
                category = if ($v.Type -eq "image") { "Photography" } else { "Products" }
                description = ""
                tags = @()
                order = 999
            }
        }
    }
    $template | ConvertTo-Json -Depth 6 | Out-String | ForEach-Object {
        [System.IO.File]::WriteAllText($detailsPath, $_, [System.Text.UTF8Encoding]::new($false))
    }
    Write-Host "Created js/details.json - open it and give each reel a title/description." -ForegroundColor Yellow
}

# --- Load details ---------------------------------------------------------
$details = @{}
if (Test-Path -LiteralPath $detailsPath) {
    $obj = Get-Content -LiteralPath $detailsPath -Raw | ConvertFrom-Json
    foreach ($p in $obj.PSObject.Properties) {
        $details[$p.Name] = $p.Value
    }
}

# --- Probe + merge --------------------------------------------------------
function Get-DurationSec($file) {
    $json = & $ffprobe -v error -select_streams v:0 -show_entries stream=duration -of json $file 2>$null
    if (-not $json) { return [double]0 }
    try {
        $data = $json -join "`n" | ConvertFrom-Json
        $d = $data.streams[0].duration
        $n = [double]0
        if ($d -and [double]::TryParse($d, [ref]$n)) { return $n }
    } catch {}
    return [double]0
}

function Get-Resolution($file, $type) {
    if ($type -eq "image") {
        try {
            Add-Type -AssemblyName System.Drawing
            $img = [System.Drawing.Image]::FromFile($file)
            $r = "$($img.Width)x$($img.Height)"
            $img.Dispose()
            return $r
        } catch { return "" }
    }
    $json = & $ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of json $file 2>$null
    if (-not $json) { return "" }
    try {
        $data = $json -join "`n" | ConvertFrom-Json
        $w = $data.streams[0].width
        $h = $data.streams[0].height
        if ($w -and $h) { return "$w`x$h" }
    } catch {}
    return ""
}

foreach ($v in $videos) {
    $d = $details[$v.Base]
    $entries.Add([PSCustomObject]@{
        type             = "video"
        title            = if ($d.title) { $d.title } else { "Reel" }
        category         = if ($d.category) { $d.category } else { "Products" }
        description      = if ($d.description) { $d.description } else { "" }
        tags             = @($d.tags)
        src              = $v.Src
        poster           = $v.Poster
        durationSeconds  = [math]::Round((Get-DurationSec $v.Path), 2)
        resolution       = Get-Resolution $v.Path "video"
        order            = if ($d.order -ne $null) { [int]$d.order } else { 999 }
        hide             = [bool]$d.hide
    })
}

foreach ($v in $images) {
    $d = $details[$v.Base]
    $entries.Add([PSCustomObject]@{
        type             = "image"
        title            = if ($d.title) { $d.title } else { "Photo" }
        category         = if ($d.category) { $d.category } else { "Photography" }
        description      = if ($d.description) { $d.description } else { "" }
        tags             = @($d.tags)
        src              = $v.Src
        poster           = $v.Poster
        durationSeconds  = [double]0
        resolution       = Get-Resolution $v.Path "image"
        order            = if ($d.order -ne $null) { [int]$d.order } else { 999 }
        hide             = [bool]$d.hide
    })
}

# --- Sort, filter hidden, assign ids -------------------------------------
$final = $entries | Where-Object { -not $_.hide } |
    Sort-Object @{ Expression = { $_.order } }, @{ Expression = { $_.title } }, @{ Expression = { $_.src } }

$list = @()
$i = 1
foreach ($e in $final) {
    $clean = @{
        id = "v{0:D3}" -f $i
        type = $e.type
        title = $e.title
        category = $e.category
        description = $e.description
        src = $e.src
        order = $e.order
    }
    if ($e.type -eq "video") {
        $clean.poster = $e.poster
        $clean.durationSeconds = $e.durationSeconds
    }
    if ($e.resolution) { $clean.resolution = $e.resolution }
    if ($e.tags.Count -gt 0) { $clean.tags = $e.tags }
    $list += $clean
    $i++
}

# --- Write js/data.js ------------------------------------------------------
$json = $list | ConvertTo-Json -Depth 5
$content = @"
// GENERATED BY tools/regenerate.ps1 - do not edit by hand.
// Edit js/details.json for titles/descriptions/categories, then re-run the script.
window.PORTFOLIO_VIDEOS = $json;
"@
$content | ForEach-Object {
    [System.IO.File]::WriteAllText($dataPath, $_, [System.Text.UTF8Encoding]::new($false))
}

Write-Host ""
Write-Host ("Wrote js/data.js with {0} item(s)." -f $list.Count) -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Edit js/details.json to add real titles & descriptions"
Write-Host "  2. Re-run this script after any edit or media change"
Write-Host "  3. Double-click index.html to preview, or upload the folder to Netlify/GitHub Pages"
