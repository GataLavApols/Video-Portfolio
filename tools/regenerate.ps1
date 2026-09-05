# ============================================================
#  Portfolio data generator
#  Scans videos/ (including category sub-folders) and images/,
#  auto-creates a thumbnail for any video that doesn't have one,
#  merges your notes from js/details.json, and writes
#  js/data.js (used by the site).
#
#  Categories come from the sub-folder names in videos/, e.g.
#  videos/Product Reels/foo.mp4 -> "Product Reels".
#  Videos at the root of videos/ fall back to the "General"
#  category (or the category you set in js/details.json).
#
#  When to run:
#    - After adding or removing videos/images
#    - After editing js/details.json
#
#  Run it:  right-click > Run with PowerShell  (or a terminal)
#  Tip: first run also creates js/details.json so you can give
#       each reel a real title, description and order.
# ============================================================

$ErrorActionPreference = "Stop"

# --- Locate ffmpeg/ffprobe -------------------------------------------
function Find-Exe([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $wingetRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    $candidates = @()
    if (Test-Path -LiteralPath $wingetRoot) {
        $candidates += Get-ChildItem -Path $wingetRoot -Recurse -Filter ($Name + ".exe") -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
    }
    if ($candidates.Count -gt 0) { return $candidates[0] }
    return $null
}
$ffprobe = Find-Exe "ffprobe"
$ffmpeg  = Find-Exe "ffmpeg"
if (-not $ffprobe) { throw "ffprobe not found. Install ffmpeg first:  winget install Gyan.FFmpeg" }

# --- Folders -----------------------------------------------------------
$base     = Split-Path $PSScriptRoot -Parent
$videoDir = Join-Path $base "videos"
$imgDir   = Join-Path $base "images"
$jsDir    = Join-Path $base "js"
$thumbDir = Join-Path $base "thumbs"
$detailsPath = Join-Path $jsDir "details.json"
New-Item -ItemType Directory -Path $imgDir, $jsDir, $thumbDir -Force | Out-Null

function To-UrlPath([string]$p) {
    return $p.Replace([System.IO.Path]::DirectorySeparatorChar, "/").Replace([System.IO.Path]::AltDirectorySeparatorChar, "/")
}

function Get-RelativePath([string]$Root, [string]$Full) {
    $prefix = $Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if ($Full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Full.Substring($prefix.Length)
    }
    return $Full
}

function Strip-Extension([string]$p) {
    return [System.Text.RegularExpressions.Regex]::Replace($p, "\.[^.\\/]+$", "")
}

$entries = [System.Collections.Generic.List[object]]::new()

# --- Auto-thumbnail (ffmpeg frame grab) ---------------------------------
function Ensure-Thumbnail([string]$SrcPath, [string]$ThumbPath, [double]$DurationSec) {
    if (Test-Path -LiteralPath $ThumbPath) { return $true }
    if (-not $ffmpeg) { return $false }
    try {
        $dir = Split-Path $ThumbPath -Parent
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $t = 1.0
        if ($DurationSec -gt 4) { $t = [math]::Min([math]::Round($DurationSec * 0.2, 2), 5.0) }
        & $ffmpeg -hide_banner -loglevel error -y -ss $t -i $SrcPath `
            -frames:v 1 -q:v 3 -vf "scale=480:480:force_original_aspect_ratio=decrease" $ThumbPath 2>$null
    } catch { return $false }
    return (Test-Path -LiteralPath $ThumbPath)
}

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

# --- Collect video files (recursive, dedupe by relative path) ----------
$videoExts = @(".mov", ".mp4", ".mkv", ".webm", ".m4v", ".avi")
$videos = @()
$videoGroups = Get-ChildItem -LiteralPath $videoDir -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $videoExts -contains $_.Extension.ToLower() } |
    Group-Object {
        $rel = Get-RelativePath $videoDir $_.FullName
        Strip-Extension $rel
    }

foreach ($g in $videoGroups) {
    $mp4 = $g.Group | Where-Object { $_.Extension -ieq ".mp4" } | Select-Object -First 1
    $src = if ($mp4) { $mp4 } else { $g.Group | Sort-Object Extension | Select-Object -First 1 }

    $relFile  = Get-RelativePath $videoDir $src.FullName
    $relKey   = (Strip-Extension $relFile).Replace([System.IO.Path]::DirectorySeparatorChar, "/")
    $folder   = [System.IO.Path]::GetDirectoryName($relFile)
    if ($folder -eq ".") { $folder = "" }
    $folderFwd = if ($folder) { $folder.Replace([System.IO.Path]::DirectorySeparatorChar, "/") } else { "" }

    $duration = Get-DurationSec $src.FullName
    $thumbRel = if ($folderFwd) { "$folderFwd/$($src.BaseName).jpg" } else { "$($src.BaseName).jpg" }
    $thumbPath = Join-Path $thumbDir ($thumbRel.Replace("/", [System.IO.Path]::DirectorySeparatorChar))
    $hasThumb = Ensure-Thumbnail $src.FullName $thumbPath $duration

    $videos += [PSCustomObject]@{
        RelKey   = $relKey
        Folder   = $folderFwd
        Base     = $src.BaseName
        Src      = "videos/$((To-UrlPath $relFile))"
        Poster   = if ($hasThumb) { "thumbs/$((To-UrlPath $thumbRel))" } else { "videos/$((To-UrlPath $relFile))" }
        Path     = $src.FullName
        Type     = "video"
        Duration = $duration
    }
}

# --- Collect images ------------------------------------------------------
$imgExts = @(".jpg", ".jpeg", ".png", ".webp", ".gif")
$images = @()
foreach ($f in (Get-ChildItem -LiteralPath $imgDir -File -ErrorAction SilentlyContinue |
    Where-Object { $imgExts -contains $_.Extension.ToLower() })) {
    $images += [PSCustomObject]@{
        RelKey = $f.BaseName
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
        "_note" = "Optional per-reel details. Key = path relative to videos/ without extension (e.g. 'Product Reels/foo'), or just the file name. Categories come from the folder names in videos/. Set order to rearrange (1,2,3...). Leave hide: true to remove from the site without deleting the file."
        "_example" = @{
            title = "My best reel"
            description = "A short description of what this video shows."
            tags = @("hook", "product", "launch")
            order = 1
        }
    }
    $idx = 0
    foreach ($v in ($videos + $images | Sort-Object RelKey)) {
        if (-not $template.ContainsKey($v.RelKey)) {
            $idx++
            $template[$v.RelKey] = @{
                title = if ($v.Type -eq "image") { "Photo {0:D2}" -f $idx } else { "Reel {0:D2}" -f $idx }
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

foreach ($v in ($videos + $images)) {
    $d = $details[$v.RelKey]
    if (-not $d) { $d = $details[$v.Base] }   # legacy bare-name keys

    if ($v.Type -eq "video") {
        $category = if ($v.Folder) { $v.Folder } elseif ($d.category) { $d.category } else { "General" }
        $entries.Add([PSCustomObject]@{
            type             = "video"
            title            = if ($d.title) { $d.title } else { $v.Base }
            category         = $category
            description      = if ($d.description) { $d.description } else { "" }
            tags             = @($d.tags | Where-Object { $_ })
            src              = $v.Src
            poster           = $v.Poster
            durationSeconds  = [math]::Round($v.Duration, 2)
            resolution       = Get-Resolution $v.Path "video"
            order            = if ($d.order -ne $null) { [int]$d.order } else { 999 }
            hide             = [bool]$d.hide
        })
    } else {
        $entries.Add([PSCustomObject]@{
            type             = "image"
            title            = if ($d.title) { $d.title } else { "Photo" }
            category         = if ($d.category) { $d.category } else { "Photography" }
            description      = if ($d.description) { $d.description } else { "" }
            tags             = @($d.tags | Where-Object { $_ })
            src              = $v.Src
            poster           = $v.Poster
            durationSeconds  = [double]0
            resolution       = Get-Resolution $v.Path "image"
            order            = if ($d.order -ne $null) { [int]$d.order } else { 999 }
            hide             = [bool]$d.hide
        })
    }
}

# --- Sort, filter hidden, assign ids -------------------------------------
$final = $entries | Where-Object { -not $_.hide } |
    Sort-Object @{ Expression = { $_.order } }, @{ Expression = { $_.title } }, @{ Expression = { $_.src } }

$dataPath = Join-Path $jsDir "data.js"
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
// Edit js/details.json for titles/descriptions, then re-run the script.
// Categories come from the sub-folder names in videos/.
window.PORTFOLIO_VIDEOS = $json;
"@
$content | ForEach-Object {
    [System.IO.File]::WriteAllText($dataPath, $_, [System.Text.UTF8Encoding]::new($false))
}

Write-Host ""
Write-Host ("Wrote js/data.js with {0} item(s)." -f $list.Count) -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Drop videos into videos/<Category>/ - the folder name becomes its filter"
Write-Host "  2. Thumbnails are made automatically; edit js/details.json for titles"
Write-Host "  3. Re-run this script after any media change"
Write-Host "  4. Double-click index.html to preview, or upload the folder to Netlify/GitHub Pages"