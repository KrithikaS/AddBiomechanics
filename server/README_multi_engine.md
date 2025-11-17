# Multi-Engine Scripts

This directory contains scripts to run `engine.py` for multiple test_data folders in batch mode.

## Available Scripts

### 1. `run_engine_multi.py` (Recommended)
Cross-platform Python script with full feature support.

**Features:**
- ✅ Parallel and sequential processing
- ✅ Docker and local execution
- ✅ Comprehensive error handling
- ✅ Results logging and summary
- ✅ Dry-run mode
- ✅ Continue-on-error option
- ✅ Cross-platform compatibility

### 2. `run_engine_multi.sh`
Bash script for Unix-like systems (Linux, macOS).

**Features:**
- ✅ Parallel and sequential processing
- ✅ Docker and local execution
- ✅ Error handling
- ✅ Dry-run mode
- ✅ Continue-on-error option

### 3. `run_engine_multi.bat`
Windows batch script for Windows systems.

**Features:**
- ✅ Sequential processing (parallel limited)
- ✅ Docker and local execution
- ✅ Basic error handling
- ✅ Dry-run mode
- ✅ Continue-on-error option

## Usage

### Basic Usage

```bash
# Process all test_data folders in a directory
python run_engine_multi.py server/app/test_data

# Process specific folders
python run_engine_multi.py folder1 folder2 folder3

# Process with Docker
python run_engine_multi.py -d server/app/test_data

# Process in parallel
python run_engine_multi.py -p server/app/test_data

# Dry run to see what would be executed
python run_engine_multi.py --dry-run server/app/test_data
```

### Advanced Usage

```bash
# Process all test_data folders with custom output directory
python run_engine_multi.py -o ./batch_results server/app/test_data

# Process with Docker in parallel, continue on errors
python run_engine_multi.py -p -d --continue-on-error server/app/test_data

# Use custom Docker image
python run_engine_multi.py -d --docker-image my-custom-image server/app/test_data

# Process with custom engine script path
python run_engine_multi.py --engine-script custom/path/engine.py server/app/test_data
```

## Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `-p, --parallel` | Run folders in parallel | Sequential |
| `-d, --docker` | Use Docker container | Local Python |
| `-o, --output-dir DIR` | Output directory for results | `./results` |
| `--dry-run` | Show what would be run without executing | False |
| `--continue-on-error` | Continue processing other folders if one fails | False |
| `--docker-image IMAGE` | Docker image to use | `kswami235/addbio` |
| `--engine-script PATH` | Path to engine script | `engine/src/engine.py` |
| `-h, --help` | Show help message | - |

## Examples

### Example 1: Process All Test Data Folders in a Directory

```bash
# Process all test data folders in the app directory
python run_engine_multi.py server/app/test_data

# Process specific folders
python run_engine_multi.py \
    server/app/test_data/data_harvester_test_short \
    server/app/test_data/data_harvester_test_long \
    server/app/test_data/skeleton_test
```

### Example 2: Docker Processing

```bash
# Process with Docker (recommended for consistency)
python run_engine_multi.py -d server/app/test_data

# Use custom Docker image
python run_engine_multi.py -d --docker-image my-addbio-image server/app/test_data
```

### Example 3: Parallel Processing

```bash
# Process all folders in parallel (faster for independent folders)
python run_engine_multi.py -p server/app/test_data

# Parallel processing with Docker
python run_engine_multi.py -p -d server/app/test_data
```

### Example 4: Error Handling

```bash
# Continue processing even if some folders fail
python run_engine_multi.py --continue-on-error server/app/test_data

# Dry run to check what would be executed
python run_engine_multi.py --dry-run server/app/test_data
```

### Example 5: Custom Output Directory

```bash
# Save results to custom directory
python run_engine_multi.py -o ./my_results server/app/test_data

# Process with custom output and continue on error
python run_engine_multi.py -o ./results --continue-on-error server/app/test_data
```

## Output Structure

The scripts create the following output structure:

```
results/
├── processing_results.json          # Summary of all processing results
├── folder1/                         # Results for folder1
│   ├── osim_results/               # OpenSim results
│   ├── osim_results.zip            # Zipped OpenSim results
│   ├── osim_results.b3d            # B3D file
│   └── ...                         # Other output files
├── folder2/                         # Results for folder2
│   └── ...
└── ...
```

## Results File

The `processing_results.json` file contains:

```json
{
  "total_folders": 3,
  "successful": 2,
  "failed": 1,
  "total_duration": 45.2,
  "configuration": {
    "parallel": false,
    "docker": true,
    "dry_run": false,
    "continue_on_error": true,
    "docker_image": "kswami235/addbio"
  },
  "results": [
    {
      "folder": "folder1",
      "success": true,
      "duration": 15.3,
      "timestamp": "2024-01-15T10:30:00"
    },
    {
      "folder": "folder2",
      "success": false,
      "duration": 5.1,
      "error": "Command failed with return code 1",
      "timestamp": "2024-01-15T10:35:00"
    }
  ],
  "timestamp": "2024-01-15T10:40:00"
}
```

## Folder Structure Requirements

The input folders should follow the expected structure for `engine.py`:

```
folder_name/
├── _subject.json                    # Subject configuration
├── unscaled_generic.osim           # OpenSim model file
├── trials/                         # Trial data
│   ├── trial1/
│   │   ├── grf.mot                 # Ground reaction forces
│   │   ├── markers.trc             # Marker data
│   │   └── segment_1/              # Segmented data
│   │       ├── data.csv
│   │       ├── review.json
│   │       └── REVIEWED
│   └── trial2/
│       └── ...
└── Geometry/                       # Geometry files (optional)
    └── ...
```

## Original Folder Handling

If a folder name ends with `_original`, the script will:

1. Copy the folder to the output directory
2. Remove the `_original` suffix from the copied folder name
3. Process the copied folder

This is useful for preserving original data while processing copies.

## Error Handling

### Continue on Error
Use `--continue-on-error` to process all folders even if some fail:

```bash
python run_engine_multi.py --continue-on-error folder1 folder2 folder3
```

### Error Logging
Failed processing attempts are logged in the results file with:
- Error messages
- Processing duration
- Timestamp

## Performance Tips

### Parallel Processing
Use parallel processing for independent folders:

```bash
python run_engine_multi.py -p folder1 folder2 folder3
```

**Note:** Parallel processing is limited by system resources. The script uses a maximum of 4 parallel workers by default.

### Docker vs Local
- **Docker**: More consistent environment, recommended for production
- **Local**: Faster startup, useful for development

## Troubleshooting

### Common Issues

1. **Folder not found**
   ```
   ERROR: Folder does not exist: folder_name
   ```
   Solution: Check the folder path and ensure it exists.

2. **Docker not found**
   ```
   ERROR: docker: command not found
   ```
   Solution: Install Docker or use local processing (`-d` flag).

3. **Permission denied**
   ```
   ERROR: Permission denied
   ```
   Solution: Check file permissions and ensure write access to output directory.

4. **Engine script not found**
   ```
   ERROR: engine script not found
   ```
   Solution: Check the `--engine-script` path or use the default path.

### Debug Mode

Use dry-run mode to debug:

```bash
python run_engine_multi.py --dry-run folder1 folder2
```

This will show what commands would be executed without actually running them.

## Platform-Specific Notes

### Windows
- Use `run_engine_multi.bat` for basic functionality
- Use `run_engine_multi.py` for full features
- Ensure Python 3 is in PATH

### Linux/macOS
- Use `run_engine_multi.sh` for basic functionality
- Use `run_engine_multi.py` for full features
- Ensure Python 3 is installed

### Docker
- Ensure Docker is running
- Use `--platform linux/amd64` for cross-platform compatibility
- Check Docker image availability

## Integration with Existing Workflows

### CI/CD Integration
```bash
# Process test data in CI pipeline
python run_engine_multi.py -p -d --continue-on-error \
    --output-dir ./ci_results \
    server/app/test_data/*
```

### Batch Processing
```bash
# Process all folders in a directory
python run_engine_multi.py -o ./batch_results server/app/test_data/*

# Process with custom configuration
python run_engine_multi.py -p -d --docker-image my-image \
    --continue-on-error -o ./results folder1 folder2
```

## Contributing

To add new features or fix issues:

1. Test with dry-run mode first
2. Add error handling for new features
3. Update documentation
4. Test on multiple platforms

## License

Same as the main AddBiomechanics project.
