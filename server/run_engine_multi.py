#!/usr/bin/env python3
"""
run_engine_multi.py
------------------
Description: Script to run engine.py for multiple test_data folders
Usage: python run_engine_multi.py [options] [folder1] [folder2] ...

Options:
  -p, --parallel     Run folders in parallel (default: sequential)
  -d, --docker       Use Docker container (default: local Python)
  -o, --output-dir  Output directory for results (default: ./results)
  -h, --help         Show this help message
  --dry-run          Show what would be run without executing
  --continue-on-error Continue processing other folders if one fails

Examples:
  python run_engine_multi.py data_harvester_test_short data_harvester_test_long
  python run_engine_multi.py -p -d opencap_test_original
  python run_engine_multi.py --dry-run -o ./batch_results *
  python run_engine_multi.py --continue-on-error -o ./results server/app/test_data/*
"""

import os
import sys
import argparse
import subprocess
import shutil
import time
import json
from datetime import datetime
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List, Tuple, Optional


class Colors:
    """ANSI color codes for terminal output"""
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color


class MultiEngineRunner:
    """Main class for running engine.py on multiple folders"""
    
    def __init__(self, args):
        self.parallel = args.parallel
        self.use_docker = args.docker
        self.output_dir = Path(args.output_dir)
        self.dry_run = args.dry_run
        self.continue_on_error = args.continue_on_error
        self.docker_image = args.docker_image
        self.engine_script = args.engine_script
        self.folders = args.folders
        self.results = []
        
        # Create output directory
        self.output_dir.mkdir(parents=True, exist_ok=True)
    
    def print_status(self, color: str, message: str):
        """Print colored status message with timestamp"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f"{color}[{timestamp}] {message}{Colors.NC}")
    
    def print_success(self, message: str):
        self.print_status(Colors.GREEN, f"SUCCESS: {message}")
    
    def print_error(self, message: str):
        self.print_status(Colors.RED, f"ERROR: {message}")
    
    def print_warning(self, message: str):
        self.print_status(Colors.YELLOW, f"WARNING: {message}")
    
    def print_info(self, message: str):
        self.print_status(Colors.BLUE, f"INFO: {message}")
    
    def validate_folders(self) -> bool:
        """Validate that all specified folders exist"""
        for folder in self.folders:
            if not os.path.exists(folder):
                self.print_error(f"Folder does not exist: {folder}")
                return False
            if not os.path.isdir(folder):
                self.print_error(f"Path is not a directory: {folder}")
                return False
        return True
    
    def process_folder(self, folder_path: str) -> Tuple[bool, str, float]:
        """Process a single folder with engine.py"""
        folder_name = os.path.basename(folder_path)
        output_path = self.output_dir / folder_name
        
        self.print_info(f"Processing folder: {folder_path}")
        
        # Create output directory
        output_path.mkdir(parents=True, exist_ok=True)
        
        # Copy original folder if it has _original suffix
        working_folder = output_path / folder_name
        if folder_name.endswith("_original"):
            clean_name = folder_name[:-9]  # Remove "_original" suffix
            working_folder = output_path / clean_name
            self.print_info(f"Copying {folder_path} to {working_folder}")
            if not self.dry_run:
                if working_folder.exists():
                    shutil.rmtree(working_folder)
                shutil.copytree(folder_path, working_folder)
        else:
            self.print_info(f"Using folder directly: {folder_path}")
            working_folder = Path(folder_path)
        
        # Run the engine
        if self.dry_run:
            self.print_info(f"DRY RUN: Would execute engine for {working_folder}")
            if self.use_docker:
                self.print_info(f"DRY RUN: docker run --rm -it --platform linux/amd64 "
                              f"-v {working_folder}:/test_data {self.docker_image} "
                              f"python3 {self.engine_script} /test_data")
            else:
                self.print_info(f"DRY RUN: python3 {self.engine_script} {working_folder}")
            return True, folder_name, 0.0
        
        start_time = time.time()
        
        try:
            if self.use_docker:
                self.print_info("Running engine in Docker container...")
                cmd = [
                    "docker", "run", "--rm", "-it",
                    "--platform", "linux/amd64",
                    "-v", f"{working_folder}:/test_data",
                    self.docker_image,
                    "python3", self.engine_script, "/test_data"
                ]
                result = subprocess.run(cmd, check=True, capture_output=True, text=True)
            else:
                self.print_info("Running engine locally...")
                cmd = ["python3", self.engine_script, str(working_folder)]
                result = subprocess.run(cmd, check=True, capture_output=True, text=True)
            
            end_time = time.time()
            duration = end_time - start_time
            self.print_success(f"Completed processing {folder_name}")
            self.print_info(f"Processing time for {folder_name}: {duration:.1f}s")
            
            return True, folder_name, duration
            
        except subprocess.CalledProcessError as e:
            end_time = time.time()
            duration = end_time - start_time
            self.print_error(f"Failed to process {folder_name}")
            self.print_error(f"Command failed with return code {e.returncode}")
            if e.stdout:
                self.print_error(f"STDOUT: {e.stdout}")
            if e.stderr:
                self.print_error(f"STDERR: {e.stderr}")
            return False, folder_name, duration
        
        except Exception as e:
            end_time = time.time()
            duration = end_time - start_time
            self.print_error(f"Unexpected error processing {folder_name}: {str(e)}")
            return False, folder_name, duration
    
    def process_folders_parallel(self):
        """Process folders in parallel"""
        self.print_info(f"Starting parallel processing of {len(self.folders)} folders...")
        
        with ThreadPoolExecutor(max_workers=min(len(self.folders), 4)) as executor:
            # Submit all tasks
            future_to_folder = {
                executor.submit(self.process_folder, folder): folder 
                for folder in self.folders
            }
            
            # Collect results as they complete
            for future in as_completed(future_to_folder):
                folder = future_to_folder[future]
                try:
                    success, folder_name, duration = future.result()
                    self.results.append({
                        'folder': folder_name,
                        'success': success,
                        'duration': duration,
                        'timestamp': datetime.now().isoformat()
                    })
                    
                    if success:
                        self.print_success(f"Parallel processing completed: {folder_name}")
                    else:
                        self.print_error(f"Parallel processing failed: {folder_name}")
                        
                except Exception as e:
                    self.print_error(f"Exception in parallel processing for {folder}: {str(e)}")
                    self.results.append({
                        'folder': folder,
                        'success': False,
                        'duration': 0.0,
                        'error': str(e),
                        'timestamp': datetime.now().isoformat()
                    })
    
    def process_folders_sequential(self):
        """Process folders sequentially"""
        self.print_info(f"Starting sequential processing of {len(self.folders)} folders...")
        
        success_count = 0
        failure_count = 0
        
        for folder in self.folders:
            success, folder_name, duration = self.process_folder(folder)
            
            self.results.append({
                'folder': folder_name,
                'success': success,
                'duration': duration,
                'timestamp': datetime.now().isoformat()
            })
            
            if success:
                success_count += 1
            else:
                failure_count += 1
                if not self.continue_on_error:
                    self.print_error(f"Stopping due to error in {folder_name} "
                                   f"(use --continue-on-error to continue)")
                    sys.exit(1)
        
        self.print_info(f"Sequential processing completed: {success_count} successful, "
                       f"{failure_count} failed")
    
    def save_results(self):
        """Save processing results to JSON file"""
        results_file = self.output_dir / "processing_results.json"
        
        summary = {
            'total_folders': len(self.folders),
            'successful': sum(1 for r in self.results if r['success']),
            'failed': sum(1 for r in self.results if not r['success']),
            'total_duration': sum(r['duration'] for r in self.results),
            'configuration': {
                'parallel': self.parallel,
                'docker': self.use_docker,
                'dry_run': self.dry_run,
                'continue_on_error': self.continue_on_error,
                'docker_image': self.docker_image if self.use_docker else None
            },
            'results': self.results,
            'timestamp': datetime.now().isoformat()
        }
        
        with open(results_file, 'w') as f:
            json.dump(summary, f, indent=2)
        
        self.print_info(f"Results saved to {results_file}")
    
    def print_summary(self):
        """Print processing summary"""
        successful = sum(1 for r in self.results if r['success'])
        failed = len(self.results) - successful
        total_duration = sum(r['duration'] for r in self.results)
        
        self.print_info("=" * 50)
        self.print_info("PROCESSING SUMMARY")
        self.print_info("=" * 50)
        self.print_info(f"Total folders: {len(self.folders)}")
        self.print_info(f"Successful: {successful}")
        self.print_info(f"Failed: {failed}")
        self.print_info(f"Total processing time: {total_duration:.1f}s")
        
        if failed > 0:
            self.print_warning("Failed folders:")
            for result in self.results:
                if not result['success']:
                    self.print_warning(f"  - {result['folder']}")
        
        self.print_info("=" * 50)
    
    def run(self):
        """Main execution method"""
        # Print configuration
        self.print_info("Configuration:")
        self.print_info(f"  Parallel: {self.parallel}")
        self.print_info(f"  Docker: {self.use_docker}")
        self.print_info(f"  Output directory: {self.output_dir}")
        self.print_info(f"  Dry run: {self.dry_run}")
        self.print_info(f"  Continue on error: {self.continue_on_error}")
        if self.use_docker:
            self.print_info(f"  Docker image: {self.docker_image}")
        self.print_info(f"  Folders to process: {len(self.folders)}")
        
        # Validate folders
        if not self.validate_folders():
            sys.exit(1)
        
        # Process folders
        if self.parallel:
            self.process_folders_parallel()
        else:
            self.process_folders_sequential()
        
        # Save results and print summary
        self.save_results()
        self.print_summary()
        
        if any(not r['success'] for r in self.results):
            self.print_warning("Some folders failed to process. Check the results file for details.")
        else:
            self.print_success("All folders processed successfully!")


def find_test_data_folders(directory_path: str) -> List[str]:
    """Find all valid test_data folders in a directory"""
    test_folders = []
    directory = Path(directory_path)
    
    if not directory.exists():
        return test_folders
    
    for item in directory.iterdir():
        if item.is_dir():
            # Check if it's a valid test_data folder
            if is_valid_test_data_folder(item):
                test_folders.append(str(item))
    
    return test_folders

def is_valid_test_data_folder(folder_path: Path) -> bool:
    """Check if a folder contains valid test_data structure"""
    # Check for common test_data indicators
    indicators = [
        '_subject.json',
        'unscaled_generic.osim',
        'trials/',
    ]
    
    found_indicators = 0
    for indicator in indicators:
        if (folder_path / indicator).exists():
            found_indicators += 1
    
    # Consider it valid if it has at least 2 indicators
    return found_indicators >= 2

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="Run engine.py for multiple test_data folders",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Process specific folders
  python run_engine_multi.py data_harvester_test_short data_harvester_test_long
  
  # Process all test_data folders in a directory
  python run_engine_multi.py server/app/test_data
  
  # Process with Docker
  python run_engine_multi.py -d server/app/test_data
  
  # Parallel processing
  python run_engine_multi.py -p server/app/test_data
  
  # Dry run to see what would be executed
  python run_engine_multi.py --dry-run server/app/test_data
  
  # Continue on error
  python run_engine_multi.py --continue-on-error server/app/test_data

Notes:
  - If a single directory path is provided, the script will scan for test_data folders
  - Folders should contain the expected data structure for engine.py
  - Use '_original' suffix for source folders (they will be copied)
  - Results will be saved in the specified output directory
  - Use --continue-on-error to process all folders even if some fail
        """
    )
    
    parser.add_argument('paths', nargs='+', help='Folders or directories to process')
    parser.add_argument('-p', '--parallel', action='store_true',
                       help='Run folders in parallel (default: sequential)')
    parser.add_argument('-d', '--docker', action='store_true',
                       help='Use Docker container (default: local Python)')
    parser.add_argument('-o', '--output-dir', default='./results',
                       help='Output directory for results (default: ./results)')
    parser.add_argument('--dry-run', action='store_true',
                       help='Show what would be run without executing')
    parser.add_argument('--continue-on-error', action='store_true',
                       help='Continue processing other folders if one fails')
    parser.add_argument('--docker-image', default='kswami235/addbio',
                       help='Docker image to use (default: kswami235/addbio)')
    parser.add_argument('--engine-script', default='engine/src/engine.py',
                       help='Path to engine script (default: engine/src/engine.py)')
    
    args = parser.parse_args()
    
    # Process paths - if it's a directory, scan for test_data folders
    all_folders = []
    for path in args.paths:
        if os.path.isfile(path):
            # Skip files
            continue
        elif os.path.isdir(path):
            # Check if it's a single test_data folder or a directory containing multiple
            if is_valid_test_data_folder(Path(path)):
                # It's a single test_data folder
                all_folders.append(path)
            else:
                # It's a directory containing multiple test_data folders
                found_folders = find_test_data_folders(path)
                if found_folders:
                    all_folders.extend(found_folders)
                else:
                    print(f"WARNING: No valid test_data folders found in {path}")
        else:
            print(f"WARNING: Path does not exist: {path}")
    
    if not all_folders:
        print("ERROR: No valid test_data folders found")
        sys.exit(1)
    
    # Update args with discovered folders
    args.folders = all_folders
    
    # Create and run the multi-engine runner
    runner = MultiEngineRunner(args)
    runner.run()


if __name__ == "__main__":
    main()
