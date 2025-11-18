#!/bin/bash

# run_engine_multi.sh
# ------------------
# Description: Bash script to run engine.py for multiple test_data folders
# Usage: ./run_engine_multi.sh [options] [directory]
# 
# Options:
#   -p, --parallel     Run folders in parallel (default: sequential)
#   -d, --docker      Use Docker container (default: local Python)
#   -o, --output-dir Output directory for results (default: ./results)
#   -h, --help        Show this help message
#   --dry-run         Show what would be run without executing
#   --continue-on-error Continue processing other folders if one fails
#
# Examples:
#   ./run_engine_multi.sh server/app/test_data
#   ./run_engine_multi.sh -p -d server/app/test_data
#   ./run_engine_multi.sh --dry-run -o ./batch_results server/app/test_data

set -e

# Default values
PARALLEL=false
USE_DOCKER=true  # Default to Docker for consistency
OUTPUT_DIR="./results"
DRY_RUN=false
CONTINUE_ON_ERROR=false
DOCKER_IMAGE="kswami235/addbio"
ENGINE_SCRIPT="engine/src/engine.py"
COMMON_OSIM_PATH=""  # Will be set relative to input directory
MAX_PARALLEL_JOBS=4  # Maximum number of parallel jobs when using -p flag

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] ${message}${NC}"
}

print_success() {
    print_status $GREEN "SUCCESS: $1"
}

print_error() {
    print_status $RED "ERROR: $1"
}

print_warning() {
    print_status $YELLOW "WARNING: $1"
}

print_info() {
    print_status $BLUE "INFO: $1"
}

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [options] [directory]

Options:
  -p, --parallel         Run folders in parallel (default: sequential)
  -d, --docker          Use Docker container (default: true)
  -l, --local           Use local Python instead of Docker
  -o, --output-dir DIR  Output directory for results (default: ./results)
  -h, --help           Show this help message
  --dry-run            Show what would be run without executing
  --continue-on-error  Continue processing other folders if one fails
  --docker-image IMAGE Docker image to use (default: kswami235/addbio)
  --common-osim PATH   Common location for unscaled_generic.osim file
  --max-jobs N         Maximum number of parallel jobs (default: 4)

Examples:
  $0 server/app/test_data
  $0 -p -d server/app/test_data
  $0 --dry-run -o ./batch_results server/app/test_data
  $0 --continue-on-error -o ./results server/app/test_data

Notes:
  - If a single directory path is provided, the script will scan for test_data folders
  - Folders should contain the expected data structure for engine.py
  - Use '_original' suffix for source folders (they will be copied)
  - Results will be saved in the specified output directory
  - Use --continue-on-error to process all folders even if some fail
EOF
}

# Function to check if a path is a valid test_data folder
is_valid_test_data_folder() {
    local folder_path=$1
    local found_indicators=0
    
    # Check for common test_data indicators
    [[ -f "$folder_path/_subject.json" ]] && ((found_indicators++))
    [[ -f "$folder_path/unscaled_generic.osim" ]] && ((found_indicators++))
    [[ -f "$folder_path/unscaled_generic_default.osim" ]] && ((found_indicators++))
    [[ -d "$folder_path/trials" ]] && ((found_indicators++))
    [[ -d "$folder_path/Geometry" ]] && ((found_indicators++))
    
    # Check if there are .trc files in the folder
    local has_trc=false
    for trc_file in "$folder_path"/*.trc; do
        if [[ -f "$trc_file" ]]; then
            has_trc=true
            break
        fi
    done
    [[ "$has_trc" == "true" ]] && ((found_indicators++))
    
    # Consider it valid if it has at least 2 indicators
    [[ $found_indicators -ge 2 ]]
}

# Function to find all valid test_data folders in a directory
find_test_data_folders() {
    local directory_path=$1
    local folders=()
    
    if [[ ! -d "$directory_path" ]]; then
        return
    fi
    
    # Scan subdirectories
    for item in "$directory_path"/*; do
        if [[ -d "$item" ]] && is_valid_test_data_folder "$item"; then
            folders+=("$item")
        fi
    done
    
    # If no subdirectories found, check if the directory itself is a test_data folder
    if [[ ${#folders[@]} -eq 0 ]] && is_valid_test_data_folder "$directory_path"; then
        folders+=("$directory_path")
    fi
    
    # Output folders (using echo for each)
    printf "Found folders: %s\n" "${folders[@]}" >&2
    for folder in "${folders[@]}"; do
        echo "$folder"
    done
}

# Function to copy common OSIM file if needed
preprocess_osim_file() {
    local working_folder=$1
    
    # If common OSIM path is provided and file doesn't exist in working folder
    if [[ -n "$COMMON_OSIM_PATH" ]] && [[ ! -f "$working_folder/unscaled_generic.osim" ]]; then
        if [[ -f "$COMMON_OSIM_PATH" ]]; then
            print_info "Copying unscaled_generic.osim from common location..."
            cp "$COMMON_OSIM_PATH" "$working_folder/unscaled_generic.osim"
        else
            print_warning "Common OSIM file not found at: $COMMON_OSIM_PATH"
        fi
    fi
}

# Function to preprocess trial files if needed
preprocess_trial_files() {
    local working_folder=$1
    local original_folder=$2
    local trials_dir="$working_folder/trials"
    
    # Check if trials directory exists
    if [[ ! -d "$trials_dir" ]]; then
        print_info "No trials directory found, creating from .trc files..."
        mkdir -p "$trials_dir"
        
        # Look for .trc files in the original folder
        print_info "DEBUG: Looking for .trc files in: $original_folder"
        for trc_file in "$original_folder"/*.trc; do
            if [[ -f "$trc_file" ]]; then
                # Extract original filename without extension
                local base_filename=$(basename "$trc_file" .trc)
                
                # Remove common prefixes like "filtered_rotated"
                local trial_name="$base_filename"
                if [[ "$trial_name" == filtered_rotated_* ]]; then
                    trial_name="${trial_name#filtered_rotated_}"
                fi
                
                # Ensure trial name is not empty
                if [[ -z "$trial_name" ]]; then
                    trial_name="trial"
                fi
                
                local trial_dir="$trials_dir/$trial_name"
                mkdir -p "$trial_dir"
                
                # Copy the .trc file as markers.trc
                cp "$trc_file" "$trial_dir/markers.trc"
                
                # Check for corresponding .mot file
                local base_name="${trc_file%.trc}"
                if [[ -f "${base_name}.mot" ]]; then
                    cp "${base_name}.mot" "$trial_dir/grf.mot"
                fi
                
                print_info "Created trial '$trial_name' from: $(basename "$trc_file")"
            fi
        done
        
        # Check if any trials were created
        if [[ ! "$(ls -A "$trials_dir")" ]]; then
            print_warning "No .trc files found to process"
        fi
    fi
}

# Function to process a single folder
process_folder() {
    local folder_path=$1
    local folder_name=$(basename "$folder_path")
    local output_folder_name="${folder_name}_addb"
    local output_path="$OUTPUT_DIR/$output_folder_name"
    
    print_info "Processing folder: $folder_path"
    
    # Create output directory
    mkdir -p "$output_path"
    
        # Copy folder to output location with _addb suffix
        local working_folder="$output_path"
        print_info "Copying $folder_path to $working_folder"
        if [[ "$DRY_RUN" == "false" ]]; then
            rm -rf "$working_folder"
            
            # Copy everything except .trc files (we'll handle those in preprocessing)
            mkdir -p "$working_folder"
            for item in "$folder_path"/*; do
                if [[ -f "$item" ]] && [[ "${item##*.}" == "trc" ]]; then
                    # Skip .trc files - they'll be handled in preprocessing
                    continue
                elif [[ -f "$item" ]] && [[ "${item##*.}" == "mot" ]]; then
                    # Skip .mot files - they'll be handled in preprocessing
                    continue
                else
                    # Copy everything else
                    cp -r "$item" "$working_folder/"
                fi
            done
            
            # Preprocess OSIM file if needed
            preprocess_osim_file "$working_folder"
            
            # Preprocess trial files if needed
            preprocess_trial_files "$working_folder" "$folder_path"
        fi
    
    # Run the engine
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would execute engine for $working_folder"
        if [[ "$USE_DOCKER" == "true" ]]; then
            print_info "DRY RUN: docker run --rm --platform linux/amd64 -v $working_folder:/test_data $DOCKER_IMAGE python3 $ENGINE_SCRIPT /test_data \"\""
        else
            print_info "DRY RUN: python3 $ENGINE_SCRIPT $working_folder \"\""
        fi
        print_info "DRY RUN: Completed for $output_folder_name"
        return 0
    fi
    
    local start_time=$(date +%s)
    
    if [[ "$USE_DOCKER" == "true" ]]; then
        print_info "Running engine in Docker container..."
        if docker run --rm \
            --platform linux/amd64 \
            -v "$working_folder:/test_data" \
            "$DOCKER_IMAGE" \
            python3 "$ENGINE_SCRIPT" /test_data ""; then
            print_success "Completed processing $folder_name"
        else
            print_error "Failed to process $folder_name"
            return 1
        fi
    else
        print_info "Running engine locally..."
        if python3 "$ENGINE_SCRIPT" "$working_folder" ""; then
            print_success "Completed processing $folder_name"
        else
            print_error "Failed to process $folder_name"
            return 1
        fi
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    print_info "Processing time for $folder_name: ${duration}s"
    
    return 0
}

# Function to process folders in parallel
process_folders_parallel() {
    local folders=("$@")
    local pids=()
    local results_file="$OUTPUT_DIR/.results"
    
    print_info "Starting parallel processing of ${#folders[@]} folders (max ${MAX_PARALLEL_JOBS} concurrent jobs)..."
    
    for folder in "${folders[@]}"; do
        # Wait for a slot if we've reached max parallel jobs
        while [[ ${#pids[@]} -ge $MAX_PARALLEL_JOBS ]]; do
            # Check for completed processes
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    wait "${pids[$i]}"
                    unset 'pids[$i]'
                fi
            done
            # Rebuild array to remove unset elements
            pids=("${pids[@]}")
            sleep 0.5
        done
        
        (
            if process_folder "$folder"; then
                echo "SUCCESS:$folder" >> "$results_file"
            else
                echo "FAILED:$folder" >> "$results_file"
            fi
        ) &
        pids+=($!)
    done
    
    # Wait for all remaining processes to complete
    for pid in "${pids[@]}"; do
        wait $pid
    done
    
    # Read results
    if [[ -f "$results_file" ]]; then
        while IFS=: read -r status folder; do
            if [[ "$status" == "SUCCESS" ]]; then
                print_success "Parallel processing completed: $folder"
            else
                print_error "Parallel processing failed: $folder"
            fi
        done < "$results_file"
        rm -f "$results_file"
    fi
}

# Function to process folders sequentially
process_folders_sequential() {
    local folders=("$@")
    local success_count=0
    local failure_count=0
    
    print_info "Starting sequential processing of ${#folders[@]} folders..."
    
    for folder in "${folders[@]}"; do
        print_info "LOOP DEBUG: Processing folder number $((success_count + failure_count + 1)): $folder"
        if process_folder "$folder"; then
            print_info "LOOP DEBUG: process_folder returned success"
            success_count=$((success_count + 1))
        else
            print_info "LOOP DEBUG: process_folder returned failure"
            failure_count=$((failure_count + 1))
            if [[ "$CONTINUE_ON_ERROR" == "false" ]]; then
                print_error "Stopping due to error in $folder (use --continue-on-error to continue)"
                exit 1
            fi
        fi
        print_info "LOOP DEBUG: End of iteration, continuing to next folder"
    done
    
    print_info "Sequential processing completed: $success_count successful, $failure_count failed"
}

# Parse command line arguments
PATHS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--parallel)
            PARALLEL=true
            shift
            ;;
        -d|--docker)
            USE_DOCKER=true
            shift
            ;;
        -l|--local)
            USE_DOCKER=false
            shift
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --continue-on-error)
            CONTINUE_ON_ERROR=true
            shift
            ;;
        --docker-image)
            DOCKER_IMAGE="$2"
            shift 2
            ;;
        --engine-script)
            ENGINE_SCRIPT="$2"
            shift 2
            ;;
        --common-osim)
            COMMON_OSIM_PATH="$2"
            shift 2
            ;;
        --max-jobs)
            MAX_PARALLEL_JOBS="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            PATHS+=("$1")
            shift
            ;;
    esac
done

# Check if any paths were provided
if [[ ${#PATHS[@]} -eq 0 ]]; then
    print_error "No paths specified"
    show_help
    exit 1
fi

# Scan paths for test_data folders
FOLDERS=()
print_info "Scanning paths for test_data folders..."

for path in "${PATHS[@]}"; do
    if [[ -f "$path" ]]; then
        print_warning "Skipping file: $path"
        continue
    elif [[ -d "$path" ]]; then
        # Set common OSIM path relative to this input directory if not already set
        if [[ -z "$COMMON_OSIM_PATH" ]]; then
            COMMON_OSIM_PATH="$path/unscaled_generic.osim"
        fi
        
        # Find test_data folders in this path
        mapfile -t found_folders < <(find_test_data_folders "$path")
        for folder in "${found_folders[@]}"; do
            if [[ -n "$folder" ]]; then
                FOLDERS+=("$folder")
                print_info "Found test_data folder: $folder"
            fi
        done
    else
        print_error "Path does not exist: $path"
    fi
done

# Check if any folders were found
if [[ ${#FOLDERS[@]} -eq 0 ]]; then
    print_error "No valid test_data folders found"
    show_help
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Print configuration
print_info "Configuration:"
print_info "  Parallel: $PARALLEL"
print_info "  Docker: $USE_DOCKER"
print_info "  Output directory: $OUTPUT_DIR"
print_info "  Dry run: $DRY_RUN"
print_info "  Continue on error: $CONTINUE_ON_ERROR"
if [[ "$USE_DOCKER" == "true" ]]; then
    print_info "  Docker image: $DOCKER_IMAGE"
fi
print_info "  Folders to process: ${#FOLDERS[@]}"

# Debug: print all folders
print_info "DEBUG: All folders in FOLDERS array: ${FOLDERS[@]}"

# Debug: print what we're passing
print_info "DEBUG: About to call processing function with ${#FOLDERS[@]} folders"
print_info "DEBUG: First element: ${FOLDERS[0]:-NONE}"
print_info "DEBUG: Second element: ${FOLDERS[1]:-NONE}"

# Process folders
if [[ "$PARALLEL" == "true" ]]; then
    process_folders_parallel "${FOLDERS[@]}"
else
    process_folders_sequential "${FOLDERS[@]}"
fi

print_success "Batch processing completed!"
