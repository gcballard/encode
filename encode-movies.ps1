
param(
    [string]$SourceDir,
    [string]$PresetJson,
    [string]$HandBrakePath = "handbrakecli",
    [string]$OutputDir = "C:\temp\encode",
[string]$FinalDest = "X:\Movies",
    [string]$ArchiveDir = "N:\temp",
    [string]$LogDir = "logs",
    [string]$PresetName = "Plex",
    [switch]$DryRun = $true,
    [switch]$Encode = $false,
    [switch]$KeepLocal,
    [switch]$NoArchive
)

# Allow -Encode to override dry run
if ($Encode) {
    $DryRun = $false
}

# Show help if required parameters are missing
if ([string]::IsNullOrWhiteSpace($SourceDir) -or [string]::IsNullOrWhiteSpace($PresetJson)) {
    Write-Host @"
SYNOPSIS
  Batch encode movie MKV files to Plex-compatible MP4 with automatic organization

USAGE
  .\encode-movies.ps1 -SourceDir <source_path> -PresetJson <preset_path> [options]

REQUIRED PARAMETERS
  -SourceDir <path>       Path to folder containing MKV files
  -PresetJson <path>      Path to HandBrake preset JSON file

OPTIONAL PARAMETERS
  -OutputDir <path>       Local temp directory for encoding (default: C:\temp\encode)
-FinalDest <path>       Final network destination (default: X:\Movies)
  -ArchiveDir <path>      Where to move source MKVs after successful copy (default: N:\temp)
  -HandBrakePath <path>   HandBrake CLI path (default: handbrakecli)
  -LogDir <path>          Log directory (default: logs)
  -DryRun                 Preview without encoding (default: enabled)
  -Encode                 Override and actually encode (equivalent to -DryRun:\$false)
  -KeepLocal              Don't delete local temp files in OutputDir after copy to FinalDest
  -NoArchive              Don't move source MKVs to ArchiveDir after successful copy

EXAMPLES
  Preview (dry run):
    .\encode-movies.ps1 -SourceDir "N:\Videos" -PresetJson .\plexDVD2025.json

  Actually encode (encodes locally, copies to X:\Movies in background):
    .\encode-movies.ps1 -SourceDir "N:\Videos" -PresetJson .\plexDVD2025.json -Encode

  Keep local files after copy:
    .\encode-movies.ps1 -SourceDir "N:\Videos" -PresetJson .\plexDVD2025.json -Encode -KeepLocal

  Custom archive directory:
    .\encode-movies.ps1 -SourceDir "N:\Videos" -PresetJson .\plexDVD2025.json -Encode -ArchiveDir "N:\temp"

OUTPUT STRUCTURE
  <OutputDir>\<MovieName>\<MovieName>.mp4               (single file)
  <OutputDir>\<MovieName>\<MovieName> - part1.mp4        (multi-part)
  <OutputDir>\<MovieName>\<Trailers>\<Name>.mp4          (extras)
  
  After encoding, copied to <FinalDest> with same structure.
  Source MKVs are moved to <ArchiveDir> once copy completes.
"@
    exit 0
}

# Set DryRun if not explicitly provided (default $true)
# Since $DryRun is a switch, $PSBoundParameters doesn't contain it
# when not passed — default already handles this

# Ensure log directory exists first
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Set up logging
$LogFile = Join-Path $LogDir "encode-movies-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Define Write-Log function early so it can be used throughout the script
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "ERROR", "SUCCESS", "WARNING")]
        [string]$Level = "INFO"
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    
    Add-Content -Path $LogFile -Value $LogEntry
    Write-Host $LogEntry
}

# Ensure directories exist
if (-not (Test-Path $SourceDir)) {
    Write-Error "Source directory '$SourceDir' does not exist."
    exit 1
}

if (-not (Test-Path $PresetJson)) {
    Write-Error "Preset JSON file '$PresetJson' does not exist."
    exit 1
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Ensure archive directory exists
if (-not $NoArchive) {
    if (-not (Test-Path $ArchiveDir)) {
        try {
            New-Item -ItemType Directory -Path $ArchiveDir -Force | Out-Null
            Write-Log "Created archive directory: $ArchiveDir" "INFO"
        }
        catch {
            Write-Log "Could not create archive directory '$ArchiveDir': $_" "WARNING"
        }
    }
}

# Verify HandBrake is available
$HandBrakeCommand = $null
try {
    $HandBrakeCommand = Get-Command $HandBrakePath -ErrorAction Stop
    Write-Log "Found HandBrake at: $($HandBrakeCommand.Source)" "INFO"
}
catch {
    Write-Log "ERROR: HandBrake CLI not found at '$HandBrakePath'. Verify HandBrake is installed and in PATH." "ERROR"
    Write-Error "HandBrake CLI not found at '$HandBrakePath'"
    exit 1
}

if ($DryRun) {
    Write-Host "========== DRY RUN MODE ==========" -ForegroundColor Yellow
    Write-Log "DRY RUN MODE - No files will be encoded" "WARNING"
}

# Extract prefix from filename by removing disc/part markers
function Get-FilenamePrefix {
    param([string]$Filename)
    
    # Remove extension
    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($Filename)
    
    # Remove disc/part markers: _A01, _D01, _CD01, _DISC01, _PART01, etc.
    $Prefix = ($BaseName -replace '(_[A-Za-z]+\d+)$', '').Trim()
    
    return $Prefix
}

# Extract disc/part number from filename
function Get-DiscNumber {
    param([string]$Filename)
    
    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($Filename)
    
    # Match patterns like _A01, _D02, _CD01, _DISC02, _PART01, etc.
    if ($BaseName -match '_([A-Za-z]+)(\d+)$') {
        $Number = [int]$matches[2]
        return $Number
    }
    
    return $null
}

# Extract track number from filename (e.g., B1_t00, A1_t01)
function Get-TrackNumber {
    param([string]$Filename)
    
    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($Filename)
    
    # Match patterns like _A1_t00, _B1_t01, -A1_t00, -B1_t01, or just A1_t00, B1_t01
    if ($BaseName -match '[_-]?([AB]\d)_t(\d+)$|^([AB]\d)_t(\d+)$') {
        $Track = if ($matches[2]) { [int]$matches[2] } else { [int]$matches[4] }
        return $Track
    }
    
    return $null
}

# Remove track label from filename
function Get-CleanedFilename {
    param([string]$Filename)
    
    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($Filename)
    
    # Remove track label: "MovieName-B1_t00" -> "MovieName" or "B1_t00" -> ""
    $Cleaned = $BaseName -replace '[_-]?[AB]\d_t\d+$', ''
    
    return $Cleaned.Trim()
}

# Detect directory structure mode
function Detect-DirectoryMode {
    param([string]$SourceDir)
    
    # Check for MKV files directly in SourceDir (non-recursive, depth 0)
    $DirectFiles = @(Get-ChildItem -Path $SourceDir -Filter "*.mkv" -File -ErrorAction SilentlyContinue)
    
    # Check for subdirectories containing MKV files (not recursive)
    $SubdirCount = 0
    $SubdirsWithMkv = @()
    
    try {
        $SubdirsWithMkv = @(Get-ChildItem -Path $SourceDir -Directory -ErrorAction SilentlyContinue | 
            Where-Object { 
                $mkvCount = @(Get-ChildItem -Path $_.FullName -Filter "*.mkv" -File -ErrorAction SilentlyContinue).Count
                $mkvCount -gt 0
            })
        $SubdirCount = $SubdirsWithMkv.Count
    }
    catch {
        # Subdirectory check failed, treat as flat mode
        $SubdirCount = 0
    }
    
    Write-Log "[DEBUG] Detect-DirectoryMode: DirectFiles=$($DirectFiles.Count), SubdirsWithMkv=$SubdirCount" "INFO"
    
    if ($SubdirCount -gt 0 -and $DirectFiles.Count -eq 0) {
        return "Nested"
    }
    elseif ($DirectFiles.Count -gt 0) {
        return "Flat"
    }
    else {
        return "None"
    }
}

# Define valid extra types
$ValidExtraTypes = @(
    'behindthescenes',
    'deleted',
    'featurette',
    'interview',
    'scene',
    'short',
    'trailer',
    'other'
)

# Map extra type suffix to Plex directory name
$ExtraTypeMapping = @{
    'behindthescenes' = 'Behind The Scenes'
    'deleted'         = 'Deleted Scenes'
    'featurette'      = 'Featurettes'
    'interview'       = 'Interviews'
    'scene'           = 'Scenes'
    'short'           = 'Shorts'
    'trailer'         = 'Trailers'
    'other'           = 'Other'
}

# Check if filename contains an extra type suffix
function Get-ExtraType {
    param([string]$Filename)
    
    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($Filename)
    
    # Check if filename ends with any valid extra type suffix
    foreach ($ExtraType in $ValidExtraTypes) {
        if ($BaseName -like "*-$ExtraType") {
            return $ExtraType
        }
    }
    
    return $null
}

# Extract movie name from extra filename (removes the extra suffix)
function Get-MovieNameFromExtra {
    param([string]$FilePath)
    
    # Get parent directory name - this is the movie folder, strip rip timestamps
    $MovieName = Get-CleanMovieName (Split-Path -Parent $FilePath | Split-Path -Leaf)
    return $MovieName
}

# Extract descriptive filename from extra, removing the suffix
function Get-ExtraDescriptiveName {
    param([string]$Filename)
    
    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($Filename)
    
    # Remove trailing extra type suffix (e.g., -trailer, -deleted, etc.)
    $Pattern = "-($(($ValidExtraTypes -join '|')))$"
    $DescriptiveName = $BaseName -replace $Pattern, ''
    
    return $DescriptiveName.Trim()
}

# Check if file is an extra
function IsExtra {
    param([string]$Filename)
    return (Get-ExtraType $Filename) -ne $null
}

# Detect source pixel aspect ratio from a HandBrake scan so anamorphic DVD
# sources do not inherit an invalid PAR from the preset.
function Get-SourcePixelAspectRatio {
    param(
        [string]$InputFile,
        [string]$HandBrakePath
    )

    $scanOutput = & $HandBrakePath -i $InputFile --scan --title 1 2>&1
    $scanExitCode = $LASTEXITCODE

    if ($scanExitCode -ne 0) {
        Write-Log "Warning: Could not scan source aspect ratio for $InputFile (exit code: $scanExitCode). Continuing without an override." "WARNING"
        return $null
    }

    foreach ($line in $scanOutput) {
        if ($line -match 'pixel aspect:\s*(\d+)\s*/\s*(\d+)') {
            $parWidth = [int]$matches[1]
            $parHeight = [int]$matches[2]

            if ($parWidth -gt 0 -and $parHeight -gt 0) {
                return "$parWidth`:$parHeight"
            }
        }
    }

    foreach ($line in $scanOutput) {
        if ($line -match 'using bitstream PAR\s+(\d+):(\d+)') {
            $parWidth = [int]$matches[1]
            $parHeight = [int]$matches[2]

            if ($parWidth -gt 0 -and $parHeight -gt 0) {
                return "$parWidth`:$parHeight"
            }
        }
    }

    Write-Log "Warning: Could not detect a valid source aspect ratio for $InputFile. Continuing without an override." "WARNING"
    return $null
}

function Get-HandBrakeArguments {
    param(
        [string]$InputFile,
        [string]$OutputPath,
        [string]$PresetJson,
        [string]$PresetName,
        [string]$SourcePixelAspectRatio,
        [switch]$UseSoftwareX265
    )

    $arguments = @(
        "-i", $InputFile,
        "-o", $OutputPath,
        "--preset-import-file", $PresetJson,
        "--preset", $PresetName
    )

    if (-not [string]::IsNullOrWhiteSpace($SourcePixelAspectRatio)) {
        $arguments += @("--pixel-aspect", $SourcePixelAspectRatio)
    }

    if ($UseSoftwareX265) {
        $arguments += @("-e", "x265")
    }

    return $arguments
}

# Encode file with automatic x265 fallback
function Invoke-HandBrakeEncoding {
    param(
        [string]$InputFile,
        [string]$OutputPath,
        [string]$PresetJson,
        [string]$PresetName,
        [string]$HandBrakePath,
        [bool]$DryRun = $false,
        [string]$Description = ""
    )

    $sourcePixelAspectRatio = $null
    if (-not $DryRun) {
        $sourcePixelAspectRatio = Get-SourcePixelAspectRatio -InputFile $InputFile -HandBrakePath $HandBrakePath
        if (-not [string]::IsNullOrWhiteSpace($sourcePixelAspectRatio) -and $sourcePixelAspectRatio -ne "1:1") {
            Write-Log "Detected source pixel aspect ratio $sourcePixelAspectRatio for $InputFile" "INFO"
        }
    }

    $baseArguments = Get-HandBrakeArguments -InputFile $InputFile -OutputPath $OutputPath -PresetJson $PresetJson -PresetName $PresetName -SourcePixelAspectRatio $sourcePixelAspectRatio

    if ($DryRun) {
        $commandPreview = ($baseArguments | ForEach-Object {
            if ($_ -match '\s') { "`"$_`"" } else { $_ }
        }) -join ' '
        Write-Log "[DRY RUN] Would execute: & $HandBrakePath $commandPreview" "INFO"
        return @{ Success = $true; Fallback = $false; ExitCode = 0; Error = "" }
    }

    # First attempt: Use the preset as-is
    Write-Log "Attempt 1/2: Encoding with preset $PresetName" "INFO"
    $output = & $HandBrakePath @baseArguments 2>&1
    $exitCode = $LASTEXITCODE

    # Log HandBrake output
    $output | ForEach-Object { Write-Log $_ "INFO" }

    # Check for a HandBrake crash and retry with software x265.
    if ($exitCode -eq -1073741676) {
        Write-Log "HandBrake crash detected (exit code -1073741676). Retrying with software x265 encoder..." "WARNING"

        # Remove the output file if it was partially created
        if (Test-Path $OutputPath) {
            try {
                Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
            }
            catch {
                Write-Log "Warning: Could not clean up partial output file: $OutputPath" "WARNING"
            }
        }

        # Second attempt: Use x265 software encoder fallback
        Write-Log "Attempt 2/2: Encoding with x265 software encoder fallback" "INFO"
        $fallbackArguments = Get-HandBrakeArguments -InputFile $InputFile -OutputPath $OutputPath -PresetJson $PresetJson -PresetName $PresetName -SourcePixelAspectRatio $sourcePixelAspectRatio -UseSoftwareX265
        $output = & $HandBrakePath @fallbackArguments 2>&1
        $exitCode = $LASTEXITCODE

        # Log HandBrake output
        $output | ForEach-Object { Write-Log $_ "INFO" }

        if ($exitCode -eq 0) {
            Write-Log "Successfully encoded with x265 fallback: $Description" "SUCCESS"
            return @{ Success = $true; Fallback = $true; ExitCode = 0; Error = "" }
        }
        else {
            Write-Log "Failed to encode with x265 fallback - Exit code: $exitCode" "ERROR"
            return @{ Success = $false; Fallback = $true; ExitCode = $exitCode; Error = "Failed with x265 fallback (exit code $exitCode)" }
        }
    }
    elseif ($exitCode -eq 0) {
        Write-Log "Successfully encoded: $Description" "SUCCESS"
        return @{ Success = $true; Fallback = $false; ExitCode = 0; Error = "" }
    }
    else {
        Write-Log "Failed to encode - Exit code: $exitCode" "ERROR"
        return @{ Success = $false; Fallback = $false; ExitCode = $exitCode; Error = "HandBrake returned exit code $exitCode" }
    }
}

# Check if a name looks generic (auto-generated, non-descriptive)
function Test-GenericName {
    param([string]$Name)

    $Name = $Name.Trim()

    if ([string]::IsNullOrWhiteSpace($Name)) { return $true }

    if ($Name.Length -le 3) { return $true }

    if ($Name -match '^[a-z]+\d+$' -or $Name -match '^\d+[a-z]+$') { return $true }

    if ($Name -match '^\d+$') { return $true }

    return $false
}

# Remove rip timestamp suffixes from names (e.g., HANNA_20260516_194515 -> HANNA)
function Get-CleanMovieName {
    param([string]$Name)
    # Strip _YYYYMMDD_HHMMSS or _YYYYMMDD at end of name
    $Cleaned = $Name -replace '_\d{8}(_\d{6})?$', ''
    return $Cleaned.Trim('_')
}
$MkvFiles = @(Get-ChildItem -Path $SourceDir -Filter "*.mkv" -File -Recurse | Sort-Object Name)

if ($MkvFiles.Count -eq 0) {
    Write-Log "No MKV files found in $SourceDir" "WARNING"
    exit 0
}

Write-Log "Found $($MkvFiles.Count) MKV files in $SourceDir" "INFO"

# Auto-detect directory mode
$DirectoryMode = Detect-DirectoryMode -SourceDir $SourceDir
Write-Log "Directory mode: $DirectoryMode" "INFO"

# Separate extras from regular movies
$MovieFiles = @()
$ExtraFiles = @()

foreach ($File in $MkvFiles) {
    if (IsExtra $File.Name) {
        $ExtraFiles += $File
    }
    else {
        $MovieFiles += $File
    }
}

if ($ExtraFiles.Count -gt 0) {
    Write-Log "Found $($ExtraFiles.Count) extra file(s)" "INFO"
}

# Group files based on directory mode
$GroupedFiles = @{}

if ($DirectoryMode -eq "Nested") {
    Write-Log "Processing nested mode (directories contain movies)" "INFO"
    
    # Group by subdirectory name, stripping rip timestamps
    $GroupedFiles = $MovieFiles | Group-Object { 
        Get-CleanMovieName (Split-Path (Split-Path $_.FullName -Parent) -Leaf)
    } -AsHashTable -AsString
}
else {
    Write-Log "Processing flat mode (files with prefixes)" "INFO"

    # If the filename prefix looks generic, use parent directory name instead
    $GroupedFiles = $MovieFiles | Group-Object {
        $prefix = Get-FilenamePrefix $_.Name
        if (Test-GenericName $prefix) {
            $parentDir = Get-CleanMovieName (Split-Path $_.DirectoryName -Leaf)
            Write-Log "Generic filename '$($_.Name)' detected — using parent folder '$parentDir' as movie name" "INFO"
            $parentDir
        } else {
            Get-CleanMovieName $prefix
        }
    } -AsHashTable -AsString
}

Write-Log "Grouped files into $($GroupedFiles.Count) movie(s)" "INFO"

# Statistics
$SuccessCount = 0
$FailureCount = 0
$FailureLog = @()  # Track failed files with reasons

$CopyJobs = @()  # Track background copy jobs
$MoviesWithExtras = @{}  # Track which movies have extras (affects flat vs subfolder output)
$MovieSourceFiles = @{}  # Track source files per movie for archival
$GroupTotalFiles = @{}   # Track total files per movie group (for safety check)
$ExtrasPerMovie = @{}    # Count extras per movie (added to group total)
$DryRunPlan = @()        # Table-friendly dry-run summary of planned encodes
$DryRunCopies = @()      # Table-friendly dry-run summary of planned copies

# Process extras first
foreach ($Extra in $ExtraFiles) {
    # Get movie name based on directory mode
    $MovieName = if ($DirectoryMode -eq "Nested") {
        # In nested mode, parent of parent is the movie dir
        Get-CleanMovieName (Split-Path (Split-Path $Extra.FullName -Parent) -Leaf)
    }
    else {
        # In flat mode, use parent directory name
        Get-MovieNameFromExtra $Extra.FullName
    }
    
    $MoviesWithExtras[$MovieName] = $true
    if (-not $ExtrasPerMovie.ContainsKey($MovieName)) { $ExtrasPerMovie[$MovieName] = 0 }
    $ExtrasPerMovie[$MovieName]++
    
    $ExtraType = Get-ExtraType $Extra.Name
    $PlexDirectory = $ExtraTypeMapping[$ExtraType]
    $DescriptiveName = Get-ExtraDescriptiveName $Extra.Name
    
    Write-Log "[DEBUG] Extra: $($Extra.Name) -> MovieName: $MovieName (Mode: $DirectoryMode)" "INFO"
    
    # Create movie directory and extras subdirectory
    $MovieDir = Join-Path $OutputDir $MovieName
    $ExtraDir = Join-Path $MovieDir $PlexDirectory
    
    Write-Log "[DEBUG] MovieDir: $MovieDir, ExtraDir: $ExtraDir" "INFO"
    
    if (-not (Test-Path $ExtraDir)) {
        try {
            New-Item -ItemType Directory -Path $ExtraDir -Force | Out-Null
            if (-not (Test-Path $ExtraDir)) {
                Write-Log "Failed to create directory: $ExtraDir" "ERROR"
                $FailureLog += @{
                    File = $Extra.FullName
                    Type = "Extra"
                    ExitCode = -1
                    Error = "Failed to create output directory"
                }
                $FailureCount++
                continue
            }
        }
        catch {
            Write-Log "Error creating directory ${ExtraDir}: $_" "ERROR"
            $FailureLog += @{
                File = $Extra.FullName
                Type = "Extra"
                ExitCode = -1
                Error = "Failed to create output directory: $($_.Exception.Message)"
            }
            $FailureCount++
            continue
        }
    }
    
    $OutputFileName = "$DescriptiveName.mp4"
    $OutputPath = Join-Path $ExtraDir $OutputFileName

    Write-Log "Encoding extra [$ExtraType]: $($Extra.Name) -> $PlexDirectory/$OutputFileName" "INFO"
    Write-Log "[DEBUG] Full output path: $OutputPath" "INFO"

    if ($DryRun) {
        $DryRunPlan += [PSCustomObject]@{
            Movie  = $MovieName
            Kind   = "Extra: $ExtraType"
            Source = $Extra.Name
            Output = $OutputPath
        }
    }
    
    $result = Invoke-HandBrakeEncoding -InputFile $Extra.FullName -OutputPath $OutputPath -PresetJson $PresetJson -PresetName $PresetName -HandBrakePath $HandBrakePath -DryRun $DryRun -Description "extra $ExtraType of $MovieName"
    
    if ($result.Success) {
        $SuccessCount++
        if (-not $MovieSourceFiles.ContainsKey($MovieName)) {
            $MovieSourceFiles[$MovieName] = @()
        }
        $MovieSourceFiles[$MovieName] += $Extra.FullName
    }
    else {
        $FailureLog += @{
            File = $Extra.FullName
            Type = "Extra"
            ExitCode = $result.ExitCode
            Fallback = $result.Fallback
            Error = $result.Error
        }
        $FailureCount++
    }
}

# Process each movie group
foreach ($GroupKey in ($GroupedFiles.Keys | Sort-Object)) {
    $Files = $GroupedFiles[$GroupKey]
    $GroupHadSuccess = $false
    
    # Determine movie name based on mode
    $MovieName = if ($DirectoryMode -eq "Nested") {
        $GroupKey
    }
    else {
        $GroupKey
    }
    
    $UseSubfolder = $Files.Count -gt 1 -or $MoviesWithExtras.ContainsKey($MovieName)
    $GroupTotalFiles[$MovieName] = $Files.Count + $(if ($ExtrasPerMovie.ContainsKey($MovieName)) { $ExtrasPerMovie[$MovieName] } else { 0 })
    
if ($Files.Count -eq 1) {
        $File = $Files[0]
        
        if ($UseSubfolder) {
            $MovieDir = Join-Path $OutputDir $MovieName
            if (-not (Test-Path $MovieDir)) {
                New-Item -ItemType Directory -Path $MovieDir -Force | Out-Null
            }
            $OutputFileName = "$MovieName.mp4"
            $OutputPath = Join-Path $MovieDir $OutputFileName
        }
        else {
            $OutputFileName = "$MovieName.mp4"
            $OutputPath = Join-Path $OutputDir $OutputFileName
        }
        Write-Log "Encoding movie: $($File.Name) -> $OutputFileName" "INFO"

        if ($DryRun) {
            $DryRunPlan += [PSCustomObject]@{
                Movie  = $MovieName
                Kind   = "Movie"
                Source = $File.Name
                Output = $OutputPath
            }
        }
        
        $result = Invoke-HandBrakeEncoding -InputFile $File.FullName -OutputPath $OutputPath -PresetJson $PresetJson -PresetName $PresetName -HandBrakePath $HandBrakePath -DryRun $DryRun -Description $File.Name
        
        if ($result.Success) {
            $SuccessCount++
            $GroupHadSuccess = $true
            if (-not $MovieSourceFiles.ContainsKey($MovieName)) {
                $MovieSourceFiles[$MovieName] = @()
            }
            $MovieSourceFiles[$MovieName] += $File.FullName
        }
        else {
            $FailureLog += @{
                File = $File.FullName
                Type = "Movie"
                Prefix = $MovieName
                ExitCode = $result.ExitCode
                Fallback = $result.Fallback
                Error = $result.Error
            }
            $FailureCount++
        }
    }
    else {
        # Multiple files - create directory and encode each as partX or by track number
        $MovieDir = Join-Path $OutputDir $MovieName
        
        if (-not (Test-Path $MovieDir)) {
            try {
                New-Item -ItemType Directory -Path $MovieDir -Force | Out-Null
                if (-not (Test-Path $MovieDir)) {
                    Write-Log "Failed to create directory: $MovieDir" "ERROR"
                    $FailureLog += @{
                        File = "$MovieName (directory)"
                        Type = "Movie"
                        Prefix = $MovieName
                        ExitCode = -1
                        Error = "Failed to create output directory"
                    }
                    $FailureCount += $Files.Count
                    continue
                }
            }
            catch {
                Write-Log "Error creating directory ${MovieDir}: $_" "ERROR"
                $FailureLog += @{
                    File = "$MovieName (directory)"
                    Type = "Movie"
                    Prefix = $MovieName
                    ExitCode = -1
                    Error = "Failed to create output directory: $($_.Exception.Message)"
                }
                $FailureCount += $Files.Count
                continue
            }
        }
        
        $partCount = $Files.Count
        $msg = "Processing multi-part movie: " + $MovieName + " (" + $partCount + " parts)"
        Write-Log $msg "INFO"
        
        # Sort files by track number (nested mode) or disc number (flat mode)
        $SortedFiles = if ($DirectoryMode -eq "Nested") {
            Write-Log "Sorting by track number (nested mode)" "INFO"
            $Files | Sort-Object { 
                $track = Get-TrackNumber $_.Name
                if ($null -eq $track) { 9999 } else { $track }
            }
        }
        else {
            Write-Log "Sorting by disc number (flat mode)" "INFO"
            $Files | Sort-Object { Get-DiscNumber $_.Name }
        }
        
        $PartNumber = 1
        foreach ($File in $SortedFiles) {
            $OutputFileName = "$MovieName - part$PartNumber.mp4"
            $OutputPath = Join-Path $MovieDir $OutputFileName
            
            Write-Log "Encoding part $PartNumber of $MovieName`: $($File.Name) -> $OutputFileName" "INFO"

            if ($DryRun) {
                $DryRunPlan += [PSCustomObject]@{
                    Movie  = $MovieName
                    Kind   = "Movie Part $PartNumber"
                    Source = $File.Name
                    Output = $OutputPath
                }
            }
            
            $result = Invoke-HandBrakeEncoding -InputFile $File.FullName -OutputPath $OutputPath -PresetJson $PresetJson -PresetName $PresetName -HandBrakePath $HandBrakePath -DryRun $DryRun -Description "part $PartNumber of $MovieName"
            
            if ($result.Success) {
                $SuccessCount++
                $GroupHadSuccess = $true
                if (-not $MovieSourceFiles.ContainsKey($MovieName)) {
                    $MovieSourceFiles[$MovieName] = @()
                }
                $MovieSourceFiles[$MovieName] += $File.FullName
            }
            else {
                $FailureLog += @{
                    File = $File.FullName
                    Type = "Movie (Part $PartNumber)"
                    Prefix = $MovieName
                    ExitCode = $result.ExitCode
                    Fallback = $result.Fallback
                    Error = $result.Error
                }
                $FailureCount++
            }
            
            $PartNumber++
        }
    }

    # Background copy to FinalDest if group had any success
if ($GroupHadSuccess -and -not [string]::IsNullOrWhiteSpace($FinalDest)) {
        $LocalMoviePath = if ($UseSubfolder) { Join-Path $OutputDir $MovieName } else { Join-Path $OutputDir "$MovieName.mp4" }
        $DestMoviePath = if ($UseSubfolder) { Join-Path $FinalDest $MovieName } else { Join-Path $FinalDest "$MovieName.mp4" }
        
        if ($DryRun) {
            Write-Log "[DRY RUN] Would copy '$LocalMoviePath' -> '$DestMoviePath'" "INFO"
            $DryRunCopies += [PSCustomObject]@{
                Movie       = $MovieName
                LocalPath   = $LocalMoviePath
                Destination = $DestMoviePath
            }
        }
        else {
            Write-Log "Starting background copy job for '$MovieName'" "INFO"
            if ($UseSubfolder) {
                $copyJob = Start-Job -Name "Copy-$MovieName" -ScriptBlock {
                    param($src, $dest)
                    $null = New-Item -ItemType Directory -Path $dest -Force -ErrorAction Stop
                    Copy-Item -Path (Join-Path $src '*') -Destination $dest -Recurse -Force -ErrorAction Stop
                } -ArgumentList $LocalMoviePath, $DestMoviePath
            }
            else {
                $copyJob = Start-Job -Name "Copy-$MovieName" -ScriptBlock {
                    param($src, $dest)
                    Copy-Item -Path $src -Destination $dest -Force -ErrorAction Stop
                } -ArgumentList $LocalMoviePath, $DestMoviePath
            }
            $script:CopyJobs += $copyJob
        }
    }
}

# Summary
Write-Log "========== ENCODING COMPLETE ==========" "INFO"
if ($DryRun) {
    Write-Log "DRY RUN - No files were actually encoded" "WARNING"

    Write-Host ""
    Write-Host "========== DRY RUN ENCODE PLAN ==========" -ForegroundColor Cyan
    if ($DryRunPlan.Count -gt 0) {
        $DryRunPlan |
            Sort-Object Movie, Kind, Source |
            Format-Table -Property Movie, Kind, Source, Output -AutoSize -Wrap
    }
    else {
        Write-Host "No encodes planned." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "========== DRY RUN COPY PLAN ==========" -ForegroundColor Cyan
    if ($DryRunCopies.Count -gt 0) {
        $DryRunCopies |
            Sort-Object Movie |
            Format-Table -Property Movie, LocalPath, Destination -AutoSize -Wrap
    }
    elseif (-not [string]::IsNullOrWhiteSpace($FinalDest)) {
        Write-Host "No copy jobs planned." -ForegroundColor Yellow
    }
    else {
        Write-Host "Copy skipped because -FinalDest is empty." -ForegroundColor Yellow
    }
}
Write-Log "Successful: $SuccessCount" "SUCCESS"
Write-Log "Failed: $FailureCount" "ERROR"

# Detailed failure information
if ($FailureLog.Count -gt 0) {
    Write-Log "========== FAILURE DETAILS ==========" "ERROR"
    foreach ($Failure in $FailureLog) {
        Write-Log "File: $($Failure.File)" "ERROR"
        Write-Log "  Type: $($Failure.Type)" "ERROR"
        if ($Failure.Prefix) {
            Write-Log "  Prefix: $($Failure.Prefix)" "ERROR"
        }
        Write-Log "  Exit Code: $($Failure.ExitCode)" "ERROR"
        if ($Failure.Fallback) {
            Write-Log "  Fallback Attempted: Yes (x265 software encoder)" "WARNING"
        }
        Write-Log "  Error: $($Failure.Error)" "ERROR"
    }
}

Write-Log "Log file: $LogFile" "INFO"

# Wait for background copy jobs and clean up local temp
if ($CopyJobs.Count -gt 0 -and -not $DryRun) {
    Write-Log "Waiting for $($CopyJobs.Count) background copy job(s) to complete..." "INFO"
    
    $copyFailures = 0
    foreach ($job in $CopyJobs) {
        $null = $job | Wait-Job
        $jobState = $job.State
        $jobName = $job.Name
        $movieName = $jobName -replace '^Copy-', ''
        
if ($jobState -eq 'Completed') {
            Write-Log "Copy completed: $movieName" "SUCCESS"
            if (-not $KeepLocal) {
                $localPath = Join-Path $OutputDir $movieName
                $localFilePath = "$localPath.mp4"
                if (Test-Path $localFilePath) {
                    Remove-Item -Path $localFilePath -Force -ErrorAction SilentlyContinue
                }
                elseif (Test-Path $localPath) {
                    Remove-Item -Path $localPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            if (-not $NoArchive) {
                if (-not (Test-Path $ArchiveDir)) {
                    try {
                        New-Item -ItemType Directory -Path $ArchiveDir -Force | Out-Null
                    }
                    catch {
                        Write-Log "Could not create archive directory '$ArchiveDir': $_" "WARNING"
                    }
                }
                if ($MovieSourceFiles.ContainsKey($movieName)) {
                    $allSucceeded = $MovieSourceFiles[$movieName].Count -eq $GroupTotalFiles[$movieName]
                    if ($DirectoryMode -eq "Nested" -and $allSucceeded) {
                        $sourceDir = Split-Path $MovieSourceFiles[$movieName][0] -Parent
                        if (Test-Path $sourceDir) {
                            $destDir = Join-Path $ArchiveDir (Split-Path $sourceDir -Leaf)
                            try {
                                Move-Item -Path $sourceDir -Destination $destDir -Force -ErrorAction Stop
                                Write-Log "Archived source directory: $sourceDir -> $destDir" "INFO"
                            }
                            catch {
                                Write-Log "Failed to archive directory $sourceDir -> $destDir`: $_" "WARNING"
                            }
                        }
                    }
                    else {
                        if (-not $allSucceeded) {
                            Write-Log "Partial encode for '$movieName' ($($MovieSourceFiles[$movieName].Count)/$($GroupTotalFiles[$movieName]) files) — archiving individual files" "WARNING"
                        }
                        $archiveSubDir = Join-Path $ArchiveDir $movieName
                        if (-not (Test-Path $archiveSubDir)) {
                            try {
                                New-Item -ItemType Directory -Path $archiveSubDir -Force | Out-Null
                            }
                            catch {
                                Write-Log "Could not create archive subdirectory '$archiveSubDir': $_" "WARNING"
                            }
                        }
                        foreach ($srcFile in $MovieSourceFiles[$movieName]) {
                            if (Test-Path $srcFile) {
                                $destFile = Join-Path $archiveSubDir (Split-Path $srcFile -Leaf)
try {
                                    Move-Item -Path $srcFile -Destination $destFile -Force -ErrorAction Stop
                                    Write-Log "Archived source: $srcFile -> $destFile" "INFO"
                                }
                                catch {
                                    Write-Log "Failed to archive $srcFile -> $destFile`: $_" "WARNING"
                                }
                            }
                        }
                        if ($allSucceeded) {
                            Write-Log "Archived all source files for '$movieName'" "SUCCESS"
                        }
                    }
                }
            }
        }
        else {
            $jobError = $job | Receive-Job
            Write-Log "Copy failed for $movieName`: $jobError" "ERROR"
            $copyFailures++
        }
        $job | Remove-Job
    }
    
    if ($copyFailures -eq 0 -and -not $KeepLocal) {
        if (Test-Path $OutputDir) {
            Remove-Item -Path $OutputDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Cleaned up local temp directory: $OutputDir" "INFO"
        }
    }
    elseif ($copyFailures -gt 0) {
        Write-Log "$copyFailures copy job(s) failed. Local files kept at $OutputDir for retry." "WARNING"
    }
}

if ($FailureCount -gt 0 -and -not $DryRun) {
    exit 1
}
else {
    exit 0
}
