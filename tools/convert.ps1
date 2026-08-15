# ============================================================
#  Portfolio media converter
#  Converts videos/*.mov to browser-friendly videos/*.mp4 and
#  generates a poster frame for each in thumbs/.
#
#  How to use:
#    - Drop any new .mov/.mp4/.webm/.mkv file into the videos/ folder
#    - Run this script (right-click > Run with PowerShell, or from a terminal)
#    - Then run tools/regenerate.ps1 to refresh the site's data file
#
#  The script is safe to re-run: it skips files that already have
#  an .mp4 and skips thumbnails that already exist.
# ============================================================

$ErrorActionPreference = "Stop"

# --- Locate ffmpeg -----------------------------------------------------
function Find-FFmpeg {
    $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $wingetRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    $candidates = @()
    if (Test-Path -LiteralPath $wingetRoot) {
        $candidates += Get-ChildItem -Path $wingetRoot -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
    }
    $candidates += Get-ChildItem -Path "C:\ffmpeg", "C:\ffmpeg\bin", "$env:ProgramFiles\ffmpeg\bin" -Filter ffmpeg.exe -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
    foreach ($c in $candidates) { if ($c) { return $c } }
    throw "ffmpeg not found. Install it with:  winget install Gyan.FFmpeg"
}

$ffmpeg  = Find-FFmpeg
$ffprobe = $ffmpeg -replace "ffmpeg.exe$", "ffprobe.exe"
Write-Host "Using ffmpeg: $ffmpeg" -ForegroundColor Cyan

# --- Folders ------------------------------------------------------------
$base     = Split-Path $PSScriptRoot -Parent
$videoDir = Join-Path $base "videos"
$thumbDir = Join-Path $base "thumbs"
New-Item -ItemType Directory -Path $videoDir, $thumbDir -Force | Out-Null

$inputs = Get-ChildItem -LiteralPath $videoDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in ".mov", ".mkv", ".avi", ".m4v", ".webm" }

$jobs = [System.Collections.Generic.List[object]]::new()

foreach ($input in $inputs) {
    $mp4   = Join-Path $videoDir ($input.BaseName + ".mp4")
    $thumb = Join-Path $thumbDir ($input.BaseName + ".jpg")

    if (-not (Test-Path -LiteralPath $mp4)) {
        Write-Host ("Converting {0}" -f $input.Name) -ForegroundColor Yellow
        $jobs.Add([PSCustomObject]@{
            Type   = "video"
            Output = $mp4
            Args   = @("-y", "-hide_banner", "-loglevel", "error",
                "-i", $input.FullName,
                "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                "-pix_fmt", "yuv420p",
                "-c:a", "aac", "-b:a", "160k",
                "-movflags", "+faststart",
                "-threads", "0",
                $mp4)
        })
    }

    if (-not (Test-Path -LiteralPath $thumb)) {
        Write-Host ("Generating poster {0}" -f (Split-Path $thumb -Leaf)) -ForegroundColor Yellow
        $durStr = & $ffprobe -v error -show_entries format=duration -of csv=p=0 $input.FullName
        $dur = 0.0; [double]::TryParse(($durStr | Select-Object -Last 1), [ref]$dur) | Out-Null
        $ss = if ($dur -gt 1.5) { [math]::Round($dur * 0.25, 2) } else { 0.5 }
        $jobs.Add([PSCustomObject]@{
            Type   = "thumb"
            Output = $thumb
            Args   = @("-y", "-hide_banner", "-loglevel", "error",
                "-ss", "$ss",
                "-i", $input.FullName,
                "-frames:v", "1",
                "-vf", "scale=480:-2",
                "-q:v", "3",
                "-update", "1",
                $thumb)
        })
    }
}

if ($jobs.Count -eq 0) {
    Write-Host "Everything is up to date. Nothing to convert." -ForegroundColor Green
    exit 0
}

# --- Run up to 3 ffmpeg jobs at once ------------------------------------
$running  = [System.Collections.Generic.List[object]]::new()
$queue    = $jobs
$failures = [System.Collections.Generic.List[string]]::new()
$max = 3

function Start-FFmpegJob([object]$Job) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $ffmpeg
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardError = $false
    $psi.RedirectStandardOutput = $false
    $quoted = $Job.Args | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }
    $psi.Arguments = $quoted -join ' '
    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()
    return $proc
}

while ($queue.Count -gt 0 -or $running.Count -gt 0) {
    while ($running.Count -lt $max -and $queue.Count -gt 0) {
        $job = $queue[0]
        $queue.RemoveAt(0)
        $running.Add([PSCustomObject]@{ Process = Start-FFmpegJob $job; Job = $job })
    }

    Start-Sleep -Milliseconds 500

    for ($i = $running.Count - 1; $i -ge 0; $i--) {
        $item = $running[$i]
        if ($item.Process.HasExited) {
            $label = Split-Path $item.Job.Output -Leaf
            if ($item.Process.ExitCode -eq 0 -and (Test-Path -LiteralPath $item.Job.Output)) {
                Write-Host ("OK:     {0}" -f $label) -ForegroundColor Green
            } else {
                Write-Host ("FAILED: {0}" -f $label) -ForegroundColor Red
                $failures.Add($label)
            }
            $running.RemoveAt($i)
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host ("{0} job(s) failed. Check the videos and try again." -f $failures.Count) -ForegroundColor Red
    exit 1
}
Write-Host "Done." -ForegroundColor Green
