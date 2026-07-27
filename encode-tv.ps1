param(
    [string]$SourceDir,
    [string]$DestBase,
    [string]$ShowName,
    [int]$SeasonNumber = -1,
    [string]$PresetJson,
    [string]$PresetName = "Plex",
    [string]$HandBrakePath = "handbrakecli",
    [string]$LogDir = "logs",
    [int]$StartingEpisode = 1,
    [switch]$DryRun = $true,
    [switch]$Encode = $false,
    [switch]$Help = $false
)

if ($Encode) {
    $DryRun = $false
}

# Log file
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile = Join-Path $ScriptRoot "$LogDir\encode-tv-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "ERROR", "SUCCESS", "WARNING")]
        [string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    $LogDirPath = Split-Path -Parent $LogFile
    if (-not (Test-Path $LogDirPath)) {
        New-Item -ItemType Directory -Path $LogDirPath -Force | Out-Null
    }
    Add-Content -Path $LogFile -Value $LogEntry
    Write-Host $LogEntry
}

function Show-Help {
    Write-Host @"
SYNOPSIS
  Batch encode TV show episodes from MKV to MP4 with automatic episode numbering

USAGE
  .\encode-tv.ps1 -SourceDir <source_path> -DestBase <dest_path> -ShowName <show_name> -PresetJson <preset_path> [options]

  Auto-detect seasons (source has Season 01/, Season 02/, ... subdirectories):
    .\encode-tv.ps1 -SourceDir 'N:\TV\Scrubs' -DestBase 'X:\TV' -ShowName 'Scrubs (2001)' -PresetJson .\plexDVD2025.json

  Single season explicitly:
    .\encode-tv.ps1 -SourceDir 'N:\TV\Scrubs\Season 01' -DestBase 'X:\TV' -ShowName 'Scrubs (2001)' -SeasonNumber 1 -PresetJson .\plexDVD2025.json

REQUIRED PARAMETERS
  -SourceDir <source_path>
      Path to folder containing MKV files. Can be a show root with
      Season NN/ subdirectories (auto-detected) or a single season folder.
  -DestBase <dest_path>
      Base output directory where show folders will be created
      (e.g., 'X:\TV' or 'D:\Media\TV Shows').
  -ShowName <show_name>
      TV show name used in output folder and filenames
      (e.g., 'Scrubs (2001)', 'The Office (US)').
  -PresetJson <preset_path>
      Path to HandBrake preset JSON file (e.g., '.\plexDVD2025.json').

OPTIONAL PARAMETERS
  -SeasonNumber <season_num>
      Season number. Default: auto-detect from Season NN/ subdirectories.
      Pass explicitly (e.g., 1, 2, 0 for specials) to skip auto-detect.
  -PresetName <preset_name>
      Preset name from JSON file (default: 'Plex').
  -HandBrakePath <path>
      Path to HandBrake CLI executable (default: handbrakecli).
  -StartingEpisode <episode_num>
      Starting episode number (default: 1). Only used in explicit mode.
  -DryRun
      Preview what would be encoded without running HandBrake (default: on).
  -Encode
      Actually encode files (overrides dry-run default).
  -Help
      Display this help message.

EXAMPLES
  1. Auto-detect all seasons from a show root, preview only:
     .\encode-tv.ps1 -SourceDir 'N:\TV\Scrubs' -DestBase 'X:\TV' -ShowName 'Scrubs (2001)' -PresetJson .\plexDVD2025.json

  2. Auto-detect all seasons and encode:
     .\encode-tv.ps1 -SourceDir 'N:\TV\Scrubs' -DestBase 'X:\TV' -ShowName 'Scrubs (2001)' -PresetJson .\plexDVD2025.json -Encode

  3. Single season from a specific folder:
     .\encode-tv.ps1 -SourceDir 'C:\videos\season1' -DestBase 'X:\TV' -ShowName 'Andor' -SeasonNumber 1 -PresetJson .\plexDVD2025.json -Encode

  4. Starting from episode 5:
     .\encode-tv.ps1 -SourceDir 'C:\videos\season2' -DestBase 'X:\TV' -ShowName 'The Office' -SeasonNumber 2 -PresetJson .\plex.json -StartingEpisode 5 -Encode

  5. Miniseries (Season 0):
     .\encode-tv.ps1 -SourceDir 'C:\videos\roughriders' -DestBase 'X:\TV' -ShowName 'Rough Riders (1997)' -SeasonNumber 0 -PresetJson .\plexDVD2025.json -Encode

OUTPUT STRUCTURE
  <DestBase>\<ShowName>\Season <NN>\<ShowName> - S<NN>E<NN>.mp4

  Examples:
    X:\TV\Scrubs (2001)\Season 01\Scrubs (2001) - S01E01.mp4
    X:\TV\Scrubs (2001)\Season 01\Scrubs (2001) - S01E02.mp4
    X:\TV\Andor\Season 01\Andor - S01E01.mp4
    X:\TV\Andor\Season 01\Andor - S01E02.mp4
"@
}

# Show help if requested or required params missing
if ($Help -or [string]::IsNullOrWhiteSpace($SourceDir) -or [string]::IsNullOrWhiteSpace($DestBase) -or [string]::IsNullOrWhiteSpace($ShowName) -or [string]::IsNullOrWhiteSpace($PresetJson)) {
    Show-Help
    exit 0
}

# Ensure source directory exists
if (-not (Test-Path $SourceDir)) {
    Write-Error "Source directory '$SourceDir' does not exist."
    exit 1
}

# Ensure destination base exists
if (-not (Test-Path $DestBase)) {
    if ($DryRun) {
        Write-Log "[DRY RUN] Would create destination: $DestBase" "INFO"
    }
    else {
        New-Item -ItemType Directory -Path $DestBase -Force | Out-Null
    }
}

# Show folder
$ShowFolder = Join-Path $DestBase $ShowName
if (-not (Test-Path $ShowFolder)) {
    if ($DryRun) {
        Write-Log "[DRY RUN] Would create show folder: $ShowFolder" "INFO"
    }
    else {
        New-Item -ItemType Directory -Path $ShowFolder -Force | Out-Null
    }
}

function Invoke-SeasonEncode {
    param(
        [string]$SourceDir,
        [string]$DestBase,
        [string]$ShowName,
        [int]$SeasonNumber,
        [string]$PresetJson,
        [string]$PresetName,
        [string]$HandBrakePath,
        [int]$StartingEpisode = 1,
        [switch]$DryRun
    )

    $SeasonFormatted = "{0:D2}" -f $SeasonNumber
    $SeasonFolder = Join-Path $ShowFolder ("Season " + $SeasonFormatted)

    if (-not (Test-Path $SeasonFolder)) {
        if ($DryRun) {
            Write-Log "[DRY RUN] Would create season folder: $SeasonFolder" "INFO"
        }
        else {
            New-Item -ItemType Directory -Path $SeasonFolder -Force | Out-Null
        }
    }

    Write-Log "Scanning $SourceDir for MKV files..." "INFO"

    # Find all MKV files recursively, sort by parent directory then filename
    $MkvFiles = Get-ChildItem -Path $SourceDir -Recurse -Filter "*.mkv" | Sort-Object DirectoryName, Name

    if ($MkvFiles.Count -eq 0) {
        Write-Log "No MKV files found in $SourceDir" "WARNING"
        return
    }

    Write-Log "Found $($MkvFiles.Count) files for season $SeasonNumber" "INFO"

    $EpisodeNumber = $StartingEpisode
    $SuccessCount = 0
    $FailureCount = 0

    # Print mapping table
    Write-Host ""
    Write-Host "── Episode Mapping for Season $SeasonFormatted ──" -ForegroundColor Cyan
    Write-Host ("{0,-60} {1}" -f "Source File", "Destination") -ForegroundColor Cyan
    Write-Host ("{0,-60} {1}" -f ("─" * 60), ("─" * 60)) -ForegroundColor Cyan

    $FileMappings = @()
    foreach ($File in $MkvFiles) {
        $EpisodeFormatted = "{0:D2}" -f $EpisodeNumber
        $OutputFileName = "$ShowName - S$SeasonFormatted`E$EpisodeFormatted.mp4"
        $OutputPath = Join-Path $SeasonFolder $OutputFileName
        $RelativePath = $File.Directory.Name + "\" + $File.Name
        Write-Host ("{0,-60} {1}" -f $RelativePath, $OutputPath)
        $FileMappings += [PSCustomObject]@{
            File = $File
            OutputPath = $OutputPath
            OutputFileName = $OutputFileName
            EpisodeNumber = $EpisodeNumber
        }
        $EpisodeNumber++
    }

    # Reset for actual encoding
    foreach ($Mapping in $FileMappings) {
        $HandbrakeArgs = @(
            '-i', $Mapping.File.FullName
            '-o', $Mapping.OutputPath
            '--preset-import-file', $PresetJson
            '--preset', $PresetName
        )

        if ($DryRun) {
            Write-Log "[DRY RUN] $($Mapping.File.Name) → $($Mapping.OutputPath)" "INFO"
            $SuccessCount++
        }
        else {
            Write-Log "Encoding $($Mapping.File.Name) → $($Mapping.OutputPath)" "INFO"
            & $HandBrakePath @HandbrakeArgs

            if ($LASTEXITCODE -ne 0) {
                Write-Log "Failed to encode $($Mapping.File.Name) (exit code: $LASTEXITCODE)" "ERROR"
                $FailureCount++
            }
            else {
                Write-Log "Successfully encoded $($Mapping.OutputPath)" "SUCCESS"
                $SuccessCount++
            }
        }
    }

    # Season summary
    Write-Host ""
    Write-Host "── Season $SeasonFormatted Summary ──" -ForegroundColor Cyan
    Write-Host "Source: $SourceDir" -ForegroundColor Cyan
    Write-Host "Destination: $SeasonFolder" -ForegroundColor Cyan
    Write-Host "Files found: $($MkvFiles.Count)" -ForegroundColor Cyan
    Write-Host "Successful: $SuccessCount" -ForegroundColor Green
    if ($FailureCount -gt 0) {
        Write-Host "Failed: $FailureCount" -ForegroundColor Red
    }
    Write-Host ""

    return $FailureCount
}

# ─── Main Dispatch ───────────────────────────────────────────────────────────

if ($SeasonNumber -eq -1) {
    # Auto-detect mode
    $SeasonDirs = Get-ChildItem -Path $SourceDir -Directory |
        Where-Object { $_.Name -match '^Season\s+(\d+)$' } |
        Sort-Object { [int]($_.Name -replace '\D+', '') }

    if ($SeasonDirs) {
        Write-Log "Auto-detected $($SeasonDirs.Count) season(s) in $SourceDir" "INFO"
        $GlobalFailureCount = 0
        foreach ($SeasonDir in $SeasonDirs) {
            $CurrentSeason = [int]($SeasonDir.Name -replace '\D+', '')
            Write-Log "Processing $($SeasonDir.Name)..." "INFO"
            $Failures = Invoke-SeasonEncode -SourceDir $SeasonDir.FullName -DestBase $DestBase `
                -ShowName $ShowName -SeasonNumber $CurrentSeason -PresetJson $PresetJson `
                -PresetName $PresetName -HandBrakePath $HandBrakePath -DryRun:$DryRun
            $GlobalFailureCount += $Failures
        }

        Write-Log "All seasons complete. Total failures: $GlobalFailureCount" "INFO"
        if ($GlobalFailureCount -gt 0 -and -not $DryRun) {
            exit 1
        }
        exit 0
    }
    elseif ($SourceDir -match 'Season\s+(\d+)$') {
        $CurrentSeason = [int]$matches[1]
        Write-Log "Source directory matches season pattern, processing season $CurrentSeason" "INFO"
        $Failures = Invoke-SeasonEncode -SourceDir $SourceDir -DestBase $DestBase `
            -ShowName $ShowName -SeasonNumber $CurrentSeason -PresetJson $PresetJson `
            -PresetName $PresetName -HandBrakePath $HandBrakePath -DryRun:$DryRun
        if ($Failures -gt 0 -and -not $DryRun) {
            exit 1
        }
        exit 0
    }
    else {
        Write-Log "Could not auto-detect season. No 'Season NN' subdirectories found in '$SourceDir'." "ERROR"
        Write-Log "Use -SeasonNumber to specify explicitly, or point -SourceDir to a folder containing Season NN/ subdirectories." "ERROR"
        exit 1
    }
}
else {
    # Explicit season mode
    $Failures = Invoke-SeasonEncode -SourceDir $SourceDir -DestBase $DestBase `
        -ShowName $ShowName -SeasonNumber $SeasonNumber -PresetJson $PresetJson `
        -PresetName $PresetName -HandBrakePath $HandBrakePath `
        -StartingEpisode $StartingEpisode -DryRun:$DryRun
    if ($Failures -gt 0 -and -not $DryRun) {
        exit 1
    }
    exit 0
}