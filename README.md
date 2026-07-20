# encode

PowerShell helpers for batch encoding ripped MKV media with HandBrake CLI and
organizing the results into Plex-friendly folders.

The repo currently includes two scripts:

- `encode-movies.ps1` - movie-focused batch encoder with dry-run-by-default
  behavior, extras handling, local scratch encoding, background copy, source
  archival, logging, and x265 fallback.
- `encode-tv.ps1` - TV episode encoder that numbers files into
  `Show Name - SxxExx.mp4` inside a Plex-style season folder.

## Prerequisites

- PowerShell
- HandBrake CLI available as `handbrakecli`, or pass a custom path with
  `-HandBrakePath` where supported.
- A HandBrake preset JSON file. This repo includes `plexDVD2025.json`; the
  scripts default to the preset name `Plex`.

## Movie Encoding

`encode-movies.ps1` is the main workflow for movies. It scans MKV files,
detects whether the source is flat or nested, groups multi-disc titles, detects
Plex extras, encodes locally, then copies successful output to the final movie
library.

Movie encoding is dry-run by default. Add `-Encode` to actually run HandBrake.

```powershell
# Preview what would happen
.\encode-movies.ps1 -SourceDir "N:\Videos" -PresetJson .\plexDVD2025.json

# Preview with a reusable source directory variable
$sourceDir = "D:\Video"
.\encode-movies.ps1 -SourceDir $sourceDir -PresetJson "Z:\HandbrakeStuff\plexDVD2025.json" -PresetName Plex

# Run the same command without dry run
.\encode-movies.ps1 -SourceDir $sourceDir -PresetJson "Z:\HandbrakeStuff\plexDVD2025.json" -PresetName Plex -Encode

# Actually encode, copy to X:\Movies, and archive source MKVs
.\encode-movies.ps1 -SourceDir "N:\Videos" -PresetJson .\plexDVD2025.json -Encode

# Keep the local scratch MP4s after they are copied
.\encode-movies.ps1 -SourceDir "N:\Videos" -PresetJson .\plexDVD2025.json -Encode -KeepLocal

# Leave source MKVs in place instead of archiving them
.\encode-movies.ps1 -SourceDir "N:\Videos" -PresetJson .\plexDVD2025.json -Encode -NoArchive
```

### Movie Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `-SourceDir` | Required | Folder containing source MKV files. |
| `-PresetJson` | Required | HandBrake preset JSON file. |
| `-HandBrakePath` | `handbrakecli` | HandBrake CLI executable or full path. |
| `-OutputDir` | `C:\temp\encode` | Local scratch directory used for encoding. |
| `-FinalDest` | `X:\Movies` | Final movie library destination. |
| `-ArchiveDir` | `N:\temp` | Destination for source MKVs after successful copy. |
| `-LogDir` | `logs` | Directory for timestamped logs. |
| `-PresetName` | `Plex` | Preset name inside the JSON file. |
| `-DryRun` | Enabled | Preview actions without encoding or copying. |
| `-Encode` | Off | Overrides dry run and performs the encode. |
| `-KeepLocal` | Off | Keeps local scratch files after successful copy. |
| `-NoArchive` | Off | Skips moving source MKVs to the archive directory. |

### Movie Source Layouts

Flat mode is used when MKVs are directly inside `-SourceDir`:

```text
SourceDir/
  Movie_D01.mkv
  Movie_D02.mkv
  Movie-trailer.mkv
```

Nested mode is used when each movie has its own folder:

```text
SourceDir/
  MovieName/
    MovieName_D01.mkv
    MovieName_D02.mkv
    MovieName-trailer.mkv
```

The script strips common rip suffixes such as `_YYYYMMDD_HHMMSS` and disc/part
markers such as `_D01`, `_CD01`, `_DISC01`, and `_PART01`. Generic MakeMKV-style
names such as `A1.mkv`, `B1_t00.mkv`, `title_t00.mkv`, `c2.mkv`, `t01.mkv`, or
`123.mkv` use the parent folder name as the movie name. If a folder contains
multiple generic MKVs, they are treated as parts of the same movie. If a folder
contains specifically named movie MKVs, those names are used as separate movie
names.

### Movie Output Layouts

Single movie with no extras:

```text
C:\temp\encode\MovieName.mp4
X:\Movies\MovieName.mp4
```

Movie with extras:

```text
X:\Movies\MovieName\
  MovieName.mp4
  Trailers\
    Trailer Name.mp4
  Behind The Scenes\
    Feature Name.mp4
```

Multi-part movie:

```text
X:\Movies\MovieName\
  MovieName - part1.mp4
  MovieName - part2.mp4
```

Supported Plex extra suffixes are:

- `-behindthescenes`
- `-deleted`
- `-featurette`
- `-interview`
- `-scene`
- `-short`
- `-trailer`
- `-documentary`
- `-other`

Inline extras can also use a readable movie/type/title pattern:

```text
SourceDir/
  Gettysburg (1993)/
    Gettysburg (1993).mkv
    Gettysburg (1993) - Featurette - The Battle of Gettysburg.mkv
```

That outputs:

```text
Gettysburg (1993)/
  Gettysburg (1993).mp4
  Featurettes/
    The Battle of Gettysburg.mp4
```

Extras can also be placed in Plex-style subfolders instead of using filename
suffixes:

```text
SourceDir/
  MovieName/
    MovieName.mkv
    Trailers/
      Trailer.mkv
    Deleted Scenes/
      Cut Scene.mkv
```

## TV Encoding

`encode-tv.ps1` encodes MKV files from one source directory, sorted by file
name, into a Plex-style show and season folder.

```powershell
.\encode-tv.ps1 `
  -SourceDir "C:\videos\season1" `
  -DestBase "X:\TV" `
  -ShowName "Andor" `
  -SeasonNumber 1 `
  -PresetJson .\plexDVD2025.json
```

Preview without encoding:

```powershell
.\encode-tv.ps1 `
  -SourceDir "C:\videos\season1" `
  -DestBase "X:\TV" `
  -ShowName "Andor" `
  -SeasonNumber 1 `
  -PresetJson .\plexDVD2025.json `
  -DryRun
```

TV output:

```text
X:\TV\Andor\Season 01\Andor - S01E01.mp4
X:\TV\Andor\Season 01\Andor - S01E02.mp4
```

### TV Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `-SourceDir` | Required | Folder containing episode MKVs. |
| `-DestBase` | Required | Base TV library destination. |
| `-ShowName` | Required | Show name used in folder and file names. |
| `-SeasonNumber` | Required | Season number. Use `0` for specials/miniseries. |
| `-PresetJson` | Required | HandBrake preset JSON file. |
| `-PresetName` | `Plex` | Preset name inside the JSON file. |
| `-StartingEpisode` | `1` | Episode number to start from. |
| `-DryRun` | Off | Preview commands without encoding. |
| `-Help` | Off | Show script help. |

## Logs And Recovery

Movie logs are written to:

```text
logs\encode-movies-YYYYMMDD-HHmmss.log
```

`encode-movies.ps1` continues after individual file failures, reports a final
success/failure count, and includes detailed failure entries in the log. If a
background copy fails, local encoded files are kept in `-OutputDir` so they can
be copied or retried manually.

If HandBrake exits with `-1073741676`, the movie script retries the encode with
software x265 automatically.
