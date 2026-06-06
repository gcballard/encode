param(
    [string]$SourceDir,
    [string]$DestBase,
    [string]$ShowName,
    [int]$SeasonNumber,
    [string]$PresetJson,
    [string]$PresetName = "Plex",
    [int]$StartingEpisode = 1,
    [switch]$DryRun = $false,
    [switch]$Help = $false
)

# Display help if requested or if required parameters are missing
function Show-Help {
    Write-Host @"
SYNOPSIS
  Batch encode TV show episodes from MKV to MP4 with automatic episode numbering

USAGE
  .\encode-tv.ps1 -SourceDir <source_path> -DestBase <dest_path> -ShowName <show_name> -SeasonNumber <season_num> -PresetJson <preset_path> [options]

REQUIRED PARAMETERS
  -SourceDir <source_path>
      Path to folder containing MKV files to encode
      Example: 'C:\videos\season1' or 'D:\rips\andor_s02'

  -DestBase <dest_path>
      Base output directory where TV show folders will be created
      Example: 'D:\TV Shows' or 'E:\Media\Television'

  -ShowName <show_name>
      TV show name (used in output filename)
      Example: 'Andor' or 'The Office'

  -SeasonNumber <season_num>
      Season number (numeric only). Use 0 for specials or miniseries.
      Example: 0 (for specials) or 1, 2, 3 (for regular seasons)

  -PresetJson <preset_path>
      Path to HandBrake preset JSON file
      Example: 'Z:\HandBrake\plex-fast.json' or 'C:\Presets\dvd.json'

OPTIONAL PARAMETERS
  -PresetName <preset_name>
      Preset name from JSON file (default: 'Plex')
      Example: -PresetName 'plex-fast'

  -StartingEpisode <episode_num>
      Starting episode number (default: 1)
      Example: -StartingEpisode 5

  -DryRun
      Show what would be encoded without actually running encodings

  -Help
      Display this help message

EXAMPLES
  1. Basic encoding with default settings:
     .\encode-tv.ps1 -SourceDir 'C:\videos\season1' -DestBase 'D:\TV Shows' -ShowName 'Andor' -SeasonNumber 1 -PresetJson 'Z:\HandBrake\plex-fast.json'

  2. Using a custom preset name:
     .\encode-tv.ps1 -SourceDir 'C:\videos\season1' -DestBase 'D:\TV Shows' -ShowName 'Andor' -SeasonNumber 1 -PresetJson 'Z:\HandBrake\plex-fast.json' -PresetName 'fast-720p'

  3. Starting from episode 5:
     .\encode-tv.ps1 -SourceDir 'C:\videos\season2' -DestBase 'D:\TV Shows' -ShowName 'The Office' -SeasonNumber 2 -PresetJson 'Z:\HandBrake\plex.json' -StartingEpisode 5

  4. Preview without encoding (dry-run):
     .\encode-tv.ps1 -SourceDir 'C:\videos\season1' -DestBase 'D:\TV Shows' -ShowName 'Andor' -SeasonNumber 1 -PresetJson 'Z:\HandBrake\plex-fast.json' -DryRun

  5. Encoding a miniseries (Season 0):
     .\encode-tv.ps1 -SourceDir 'C:\videos\roughriders' -DestBase 'X:\TV' -ShowName 'Rough Riders TV Miniseries (1997)' -SeasonNumber 0 -PresetJson 'Z:\HandBrake\plex-fast.json' -DryRun

  6. All options combined:
     .\encode-tv.ps1 -SourceDir 'C:\videos\season1' -DestBase 'D:\TV Shows' -ShowName 'Andor' -SeasonNumber 1 -PresetJson 'Z:\HandBrake\plex-fast.json' -PresetName 'plex-fast' -StartingEpisode 1 -DryRun

OUTPUT STRUCTURE
  Encoded files will be saved as:
  <DestBase>\<ShowName>\Season <SeasonNumber>\<ShowName> - S<SeasonNumber>E<EpisodeNumber>.mp4

  Example:
  D:\TV Shows\Andor\Season 01\Andor - S01E01.mp4
  D:\TV Shows\Andor\Season 01\Andor - S01E02.mp4
  D:\TV Shows\Andor\Season 01\Andor - S01E03.mp4
"@
}

# Check if help is requested or required parameters are missing
if ($Help -or [string]::IsNullOrWhiteSpace($SourceDir) -or [string]::IsNullOrWhiteSpace($DestBase) -or [string]::IsNullOrWhiteSpace($ShowName) -or $SeasonNumber -lt 0 -or [string]::IsNullOrWhiteSpace($PresetJson)) {
    Show-Help
    exit 0
}

if ($DryRun) {
    Write-Host "========== DRY RUN MODE ==========" -ForegroundColor Yellow
    Write-Host "No files will be encoded" -ForegroundColor Yellow
}

# Ensure source directory exists
if (-not (Test-Path $SourceDir)) {
    Write-Error "Source directory '$SourceDir' does not exist."
    exit 1
}

# Ensure destination base exists or create it
if (-not (Test-Path $DestBase)) {
    New-Item -ItemType Directory -Path $DestBase -Force
}

# Format season as two digits
$SeasonFormatted = "{0:D2}" -f $SeasonNumber

# Show folder path
$ShowFolder = Join-Path $DestBase $ShowName
if (-not (Test-Path $ShowFolder)) {
    New-Item -ItemType Directory -Path $ShowFolder -Force
}

# Season folder path
$SeasonFolder = Join-Path $ShowFolder ("Season " + $SeasonFormatted)
if (-not (Test-Path $SeasonFolder)) {
    New-Item -ItemType Directory -Path $SeasonFolder -Force
}

# Get MKV files from source, sort by name
$MkvFiles = Get-ChildItem -Path $SourceDir -Filter "*.mkv" | Sort-Object Name

# Statistics
$SuccessCount = 0
$FailureCount = 0

foreach ($File in $MkvFiles) {
    $EpisodeFormatted = "{0:D2}" -f $EpisodeNumber
    $OutputFileName = "$ShowName - S$SeasonFormatted`E$EpisodeFormatted.mp4"
    $OutputPath = Join-Path $SeasonFolder $OutputFileName

    # Handbrake CLI command
    $HandbrakeCmd = "handbrakecli -i `"$($File.FullName)`" -o `"$OutputPath`" --preset-import-file `"$PresetJson`" --preset `"$PresetName`" --pixel-aspect 8:9"

    Write-Host "Encoding $($File.Name) to $OutputFileName"
    
    if ($DryRun) {
        Write-Host "[DRY RUN] Would execute: $HandbrakeCmd" -ForegroundColor Cyan
        $SuccessCount++
    }
    else {
        Invoke-Expression $HandbrakeCmd

        if ($LASTEXITCODE -ne 0) {
            Write-Host "Failed to encode $($File.Name)" -ForegroundColor Red
            $FailureCount++
        }
        else {
            $SuccessCount++
        }
    }

    $EpisodeNumber++
}

# Summary
Write-Host ""
Write-Host "========== ENCODING COMPLETE ==========" -ForegroundColor Green
if ($DryRun) {
    Write-Host "DRY RUN - No files were actually encoded" -ForegroundColor Yellow
}
Write-Host "Successful: $SuccessCount" -ForegroundColor Green
if ($FailureCount -gt 0) {
    Write-Host "Failed: $FailureCount" -ForegroundColor Red
}

if ($FailureCount -gt 0 -and -not $DryRun) {
    exit 1
}
else {
    exit 0
}