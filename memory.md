# encode-movies.ps1 — Key Details

## Purpose
Batch encode MKV files to Plex-compatible MP4 using HandBrake CLI, with automatic organization, extras handling, and background network copy.

## Parameters
| Param | Default | Description |
|---|---|---|
| `-SourceDir` | _(required)_ | Source folder with MKV files |
| `-PresetJson` | _(required)_ | HandBrake preset JSON file |
| `-OutputDir` | `C:\temp\encode` | Local scratch directory for encoding |
| `-FinalDest` | `X:\Movies` | Final network destination (copied after encode) |
| `-ArchiveDir` | `N:\temp` | Source MKVs moved here after successful encode + copy |
| `-HandBrakePath` | `handbrakecli` | HandBrake CLI executable |
| `-PresetName` | `Plex` | Preset name from JSON |
| `-LogDir` | `logs` | Log output directory |
| `-DryRun` | `$true` | Preview without encoding (default ON for safety) |
| `-Encode` | off | Override dry-run and actually encode |
| `-KeepLocal` | off | Keep `C:\temp\encode` after copy (normally auto-cleaned) |
| `-NoArchive` | off | Skip moving source MKVs to `-ArchiveDir` after copy |

## Usage
```powershell
# Preview (dry run)
.\encode-movies.ps1 -SourceDir "N:\Videos" -PresetJson .\plexDVD2025.json

# Actually encode (local scratch, background copy to network)
.\encode-movies.ps1 -SourceDir "N:\Videos" -PresetJson .\plexDVD2025.json -Encode

# Keep local files after copy
.\encode-movies.ps1 -SourceDir "N:\Videos" -PresetJson .\plexDVD2025.json -Encode -KeepLocal

# Disable archival (keep source files in place)
.\encode-movies.ps1 -SourceDir "N:\Videos" -PresetJson .\plexDVD2025.json -Encode -NoArchive
```

## Directory Structure Detection (Auto)

**Flat mode** — MKV files directly in `-SourceDir`:
```
SourceDir/
├── Movie_D01.mkv
├── Movie-trailer.mkv
```

**Nested mode** — Each movie in its own subdirectory:
```
SourceDir/
├── MovieName/
│   ├── MovieName_D01.mkv
│   └── MovieName-trailer.mkv
```

## Filename Rules
- **Generic names** (≤3 chars, or pattern like `c2`, `t01`, `123`): output folder uses parent directory name instead
- **Disc markers**: `_D01`, `_CD01`, `_PART01`, etc. stripped for grouping
- **Track labels**: `_A1_t00`, `_B1_t01` used for sort order (nested mode)
- **Rip timestamps**: `_YYYYMMDD_HHMMSS` or `_YYYYMMDD` stripped from folder/filename automatically

## Extras Detection
Files ending with `-behindthescenes`, `-deleted`, `-featurette`, `-interview`, `-scene`, `-short`, `-trailer`, `-other` are placed into corresponding Plex subfolders (e.g., `Trailers/`, `Behind The Scenes/`).

## Output Structure (Local → Final)

**Single file, no extras** — flat (no subfolder):
```
C:\temp\encode\MovieName.mp4   →   X:\Movies\MovieName.mp4
```

**Single file with extras** — subfolder (so Plex finds the extras):
```
C:\temp\encode\MovieName\
├── MovieName.mp4
├── Trailers\...mp4
└── Behind The Scenes\...mp4

  →   X:\Movies\MovieName\*
```

**Multi-part** — subfolder:
```
C:\temp\encode\MovieName\
├── MovieName - part1.mp4
└── MovieName - part2.mp4

  →   X:\Movies\MovieName\*
```

## Performance Feature: Local Encode + Background Copy
- Encodes to `C:\temp\encode` (local SSD, fast writes)
- After each movie finishes, fires `Start-Job` to copy to network (`-FinalDest`)
- Copy runs in background — next encode starts immediately
- At end, script waits for all copy jobs, then cleans `C:\temp\encode`
- If a copy fails, local files are kept for retry

## Source Archival
After a successful background copy to `-FinalDest`, source files are moved to `-ArchiveDir` (`N:\temp` by default). Archival is independent of `-KeepLocal` — source files always move on successful copy regardless. Pass `-NoArchive` to disable.

- **Nested mode**: If *all* files in the movie group succeeded, the entire source subdirectory is moved atomically (e.g., `SourceDir\MovieName_20260516\` → `N:\temp\MovieName_20260516\`). This captures companion files (`.srt`, `.jpg`, etc.).
- **Partial failure** (nested mode) or **flat mode**: Individual source files are moved into `N:\temp\MovieName\` subdirectories. A warning is logged if not all parts succeeded.

## x265 Fallback
If NVENC crashes (exit code `-1073741676`), retries with software x265 automatically.

## Logging
- Written to `<LogDir>\encode-movies-YYYYMMDD-HHmmss.log`
- Levels: `INFO`, `SUCCESS`, `WARNING`, `ERROR`
- Summary with success/failure counts and detailed failure info

## Help
Run with no arguments or missing `-SourceDir`/`-PresetJson` to print usage.