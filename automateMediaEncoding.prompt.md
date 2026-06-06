---
name: automateMediaEncoding
description: Build a PowerShell script to automate batch media encoding with organized output, parameter handling, and error recovery.
argument-hint: Specify the media type (movies, series), organization scheme (flat, by-title, extras-separate), and any special naming conventions.
---

# Automate Media File Encoding with Organization

Help me create/enhance a PowerShell script to automate batch encoding of media files with the following requirements:

## Core Features
1. **Batch Processing**: Accept a source directory and recursively process all media files (*.mkv, *.mp4, etc.)
2. **Parameter Configuration**: Support customizable parameters for:
   - Source directory path
   - Output directory path
   - Encoding preset (JSON file + preset name)
   - HandBrake CLI path
   - Log directory

3. **File Organization**: Implement intelligent output structure:
   - Detect file types or naming patterns (e.g., extras marked with suffixes like `-trailer`, `-interview`)
   - Organize output into appropriate directory structures (e.g., Plex-compliant layouts)
   - Create directories automatically if they don't exist

4. **Dry-Run Mode**: Add a `-DryRun` switch that:
   - Shows what would be encoded
   - Displays output paths without actually running encodings
   - Helps verify organization before processing

5. **Error Handling**:
   - Validate that source and preset files exist before processing
   - Check directory creation success before encoding
   - Log all operations to timestamped log files
   - Continue processing remaining files even if individual files fail
   - Report success/failure counts at completion

6. **Logging**: Write detailed logs including:
   - Input and output paths for each file
   - Encoding commands executed
   - Any errors encountered
   - Summary statistics

Provide clear command-line usage examples and document all parameters.
