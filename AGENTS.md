# encode — AGENTS.md

## Project Overview

PowerShell scripts for batch encoding ripped MKV media with HandBrake CLI into Plex-compatible MP4 files.

## Key Files

| File | Purpose |
|---|---|
| `encode-movies.ps1` | Movie batch encoder with extras detection, multi-part grouping, background copy, archival |
| `encode-tv.ps1` | TV episode encoder, sequential numbering into SxxExx format |
| `plexDVD2025.json` | HandBrake preset (H.265 NVENC, 1080p, AAC audio) |
| `memory.md` | Developer reference card |
| `logs/` | Timestamped log output directory |

## Conventions

- **Language**: PowerShell 7+
- **No build system, no tests, no linter** — scripts are invoked directly
- **Logging**: uses `Write-Log` helper with `ValidateSet('INFO','ERROR','SUCCESS','WARNING')` — never use other level strings
- **Parameters**: always use `-SourceDir` (directory), `-PresetJson` (file path), `-PresetName`, `-DryRun`/`-Encode` switches
- **Dry-run by default**: `$DryRun = $true`; `-Encode` switch sets it to `$false`
- **Extras detection**: suffix-based (`Movie-featurette.mkv`), inline pattern (`Movie - Featurette - Title.mkv`), directory-based (`Movie/Trailers/...`)
- **Extras types**: `behindthescenes`, `deleted`, `featurette`, `interview`, `scene`, `short`, `trailer`, `documentary`, `other`
- **Multi-part grouping**: files with same prefix (after stripping `_D01`, `_CD01`, `_PART01`, `- part 2`) are grouped; in nested mode, parent folder name is the group key
- **Subdirectory logic**: a subfolder is created when a movie has >1 total associated files (multi-part parts + extras combined)
- **Regex**: use `[regex]::Escape()` for literal text in .NET regex patterns — `\Q...\E` is not supported in PowerShell/.NET

## Common Commands

```powershell
# Dry run (default)
.\encode-movies.ps1 -SourceDir "N:\Videos\Movies" -PresetJson ".\plexDVD2025.json"

# Actual encode
.\encode-movies.ps1 -SourceDir "N:\Videos\Movies" -PresetJson ".\plexDVD2025.json" -Encode

# With custom paths
.\encode-movies.ps1 -SourceDir "N:\Videos" -PresetJson "Z:\HandbrakeStuff\plexDVD2025.json" -PresetName Plex -Encode

# TV encode
.\encode-tv.ps1 -SourceDir "C:\videos\season1" -DestBase "X:\TV" -ShowName "Andor" -SeasonNumber 1 -PresetJson .\plexDVD2025.json
```

## Directory Modes

- **Flat**: MKVs directly in `-SourceDir` — grouped by filename prefix
- **Nested**: MKVs in per-movie subdirectories — grouped by parent folder name
- Detected automatically by `Detect-DirectoryMode`

## Output Layout

- Single movie, no extras → `OutputDir/MovieName.mp4`
- Movie with extras or multi-part → `OutputDir/MovieName/MovieName.mp4` (or `- part1.mp4`, `- part2.mp4`)
- Extras → `OutputDir/MovieName/{PlexDir}/{DescriptiveName}.mp4`