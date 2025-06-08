#!/bin/bash

# Enhanced Xcode Template Header Customizer
# Version: 2.0

# Check if we're running with bash
if [ -z "${BASH_VERSION:-}" ]; then
    echo "Error: This script requires bash. Please run with: bash $0" >&2
    exit 1
fi

# Check bash version (need 4.0+ for associative arrays, but we'll work with 3.2+)
if [ "${BASH_VERSINFO[0]}" -lt 3 ]; then
    echo "Error: This script requires bash 3.2 or newer. Current version: $BASH_VERSION" >&2
    exit 1
fi

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Styling
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[1;32m'
readonly RED='\033[1;31m'
readonly BLUE='\033[1;34m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BACKUP_BASE_DIR="$HOME/xctemplates_backup"
readonly CONFIG_FILE="$SCRIPT_DIR/header_config.json"
readonly LOG_FILE="$BACKUP_BASE_DIR/install.log"

# Global variables
DRY_RUN=false
LOG_LEVEL="INFO"
SELECTED_TEMPLATE="corporate"
TEMPLATE_MODE="auto"

# Logging functions
log() {
    local level=$1
    shift
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local plain_message="[$timestamp] [$level] $*"
    local colored_message="[$timestamp] [$level] $*"

    # Ensure log directory exists before writing
    if [ ! -d "$(dirname "$LOG_FILE")" ]; then
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    fi

    # Write colored message to stderr to prevent it from being captured by command substitution
    echo -e "$colored_message" >&2

    # Write plain message (without color codes) to log file
    echo "$plain_message" >> "$LOG_FILE" 2>/dev/null || true
}

log_info() { [ "$LOG_LEVEL" != "ERROR" ] && log "INFO" "$@"; }
log_warn() { log "WARN" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
handle_error() {
    log_error "$1"
    exit 1
}

# Cleanup function
cleanup() {
    if [ -n "${temp_files:-}" ]; then
        rm -f "${temp_files[@]}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Validation functions
validate_environment() {
    log_info "Validating environment..."

    # Check if running on macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        handle_error "This script is designed for macOS only"
    fi

    # Check if Xcode is installed
    if ! command -v xcodebuild &> /dev/null; then
        handle_error "Xcode is not installed or not in PATH"
    fi

    # Create backup directory
    mkdir -p "$BACKUP_BASE_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"

    log_success "Environment validation completed"
}

validate_xcode_directory() {
    local dir=$1

    if [ ! -d "$dir" ]; then
        handle_error "Directory does not exist: $dir"
    fi

    # Check if it looks like an Xcode developer directory
    if [ ! -d "$dir/Platforms" ] && [ ! -d "$dir/Templates" ]; then
        log_warn "Directory doesn't appear to contain Xcode templates, continuing anyway..."
    fi
}

check_permissions() {
    local dir=$1
    local test_file="$dir/.permission_test_$$"

    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Skipping permission check"
        return 0
    fi

    if ! touch "$test_file" 2>/dev/null; then
        handle_error "Insufficient permissions to modify $dir. Please run with sudo."
    fi

    rm -f "$test_file"
    log_info "Permission check passed"
}

# Header template configurations
get_header_template() {
    case $1 in
        "corporate")
            cat << 'EOL'
//
// ___PRODUCTNAME___
//
// Copyright © ___YEAR___ ___ORGANIZATIONNAME___. All rights reserved.
//
// Unauthorized copying of this file, via any medium is strictly prohibited.
// Proprietary and confidential.
//
// @author ___FULLUSERNAME___
//
EOL
            ;;
        "opensource")
            cat << 'EOL'
//
// ___FILENAME___
// ___PRODUCTNAME___
//
// Created by ___FULLUSERNAME___ on ___DATE___.
// Licensed under MIT License
//
EOL
            ;;
        "minimal")
            cat << 'EOL'
//
// ___FILENAME___
// Created by ___FULLUSERNAME___ on ___DATE___.
//
EOL
            ;;
        "custom")
            if [ -f "$CONFIG_FILE" ]; then
                # Simple JSON parsing for header template
                grep -A 20 '"header"' "$CONFIG_FILE" | sed -n '2,/}/p' | sed '$d'
            else
                get_header_template "corporate"
            fi
            ;;
        *)
            get_header_template "corporate"
            ;;
    esac
}

# User interface functions
show_usage() {
    cat << EOF
Enhanced Xcode Template Header Customizer

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    install     Install custom headers (default)
    rollback    Restore original files from backup
    preview     Preview changes without applying
    list        List available backups
    clean       Clean old backup files

Options:
    --dry-run           Show what would be done without making changes
    --template TYPE     Use specific header template (corporate|opensource|minimal|custom)
    --config FILE       Use custom configuration file
    --directory PATH    Specify Xcode directory path
    --help             Show this help message

Examples:
    $0 install --template opensource
    $0 rollback
    $0 preview --dry-run
    $0 clean --older-than 30
EOF
}

show_menu() {
    echo -e "${BLUE}=== Xcode Template Header Customizer ===${NC}"
    echo "1. Install custom headers"
    echo "2. Preview changes"
    echo "3. Rollback to backup"
    echo "4. List backups"
    echo "5. Select header template"
    echo "6. Clean old backups"
    echo "7. Exit"
    echo
    read -p "$(echo -e ${WHITE}Select option [1-7]:${NC} )" choice
    echo "$choice"
}

select_header_template() {
    echo -e "${WHITE}Available header templates:${NC}"
    echo "1. Corporate (default) - Full copyright and proprietary notice"
    echo "2. Open Source - MIT license friendly"
    echo "3. Minimal - Simple header with creator and date"
    echo "4. Custom - Load from config file"
    echo
    read -p "$(echo -e ${WHITE}Select template [1-4]:${NC} )" template_choice

    case $template_choice in
        1) SELECTED_TEMPLATE="corporate" ;;
        2) SELECTED_TEMPLATE="opensource" ;;
        3) SELECTED_TEMPLATE="minimal" ;;
        4) SELECTED_TEMPLATE="custom" ;;
        *) SELECTED_TEMPLATE="corporate" ;;
    esac

    log_info "Selected template: $SELECTED_TEMPLATE"
}

# Core functionality
create_backup() {
    local directory_path=$1
    local directory_name=$(basename "$directory_path")
    local backup_directory="$BACKUP_BASE_DIR/${directory_name}_$(date +'%Y-%m-%d_%H-%M-%S')"

    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would create backup at $backup_directory"
        echo "$backup_directory"
        return
    fi

    # Create backup directory first
    mkdir -p "$backup_directory"

    # Log success message
    log_success "Backup directory created: $backup_directory"

    # Return the backup directory path via stdout (this gets captured)
    echo "$backup_directory"
}

find_template_files() {
    local directory_path=$1
    local pattern=$2  # "original" or "processed" or "auto"
    local -a files=()

    if [ "${pattern:-auto}" = "original" ]; then
        # Look for files with //___FILEHEADER___ (fresh Xcode installation)
        while IFS= read -r -d $'\0' file; do
            if head -n 1 "$file" 2>/dev/null | grep -q "^//___FILEHEADER___"; then
                files+=("$file")
            fi
        done < <(find "$directory_path" -type f -name "*.swift" -print0 2>/dev/null)
    elif [ "${pattern:-auto}" = "processed" ]; then
        # Look for files with ___FILEHEADER___ (already processed by this script)
        while IFS= read -r -d $'\0' file; do
            if head -n 1 "$file" 2>/dev/null | grep -q "^___FILEHEADER___"; then
                files+=("$file")
            fi
        done < <(find "$directory_path" -type f -name "*.swift" -print0 2>/dev/null)
    else
        # Auto-detect: first try original, then processed
        while IFS= read -r -d $'\0' file; do
            local first_line=$(head -n 1 "$file" 2>/dev/null)
            if [[ "$first_line" =~ ^//___FILEHEADER___ ]]; then
                files+=("$file")
            elif [[ "$first_line" =~ ^___FILEHEADER___ ]]; then
                files+=("$file")
            fi
        done < <(find "$directory_path" -type f -name "*.swift" -print0 2>/dev/null)
    fi

    # Only print if we have files to avoid empty output
    if [ ${#files[@]} -gt 0 ]; then
        printf '%s\n' "${files[@]}"
    fi
}

detect_template_state() {
    local directory_path=$1
    local -a original_files=()
    local -a processed_files=()

    # Check for original format (//___FILEHEADER___)
    while IFS= read -r file; do
        [ -n "$file" ] && original_files+=("$file")
    done < <(find_template_files "$directory_path" "original")

    # Check for processed format (___FILEHEADER___)
    while IFS= read -r file; do
        [ -n "$file" ] && processed_files+=("$file")
    done < <(find_template_files "$directory_path" "processed")

    echo "${#original_files[@]}:${#processed_files[@]}"
}

preview_changes() {
    local directory_path=$1

    log_info "Scanning for template files..."

    # Detect what types of files we have
    local state_info=$(detect_template_state "$directory_path")
    local original_count=$(echo "$state_info" | cut -d: -f1)
    local processed_count=$(echo "$state_info" | cut -d: -f2)

    if [ "$original_count" -eq 0 ] && [ "$processed_count" -eq 0 ]; then
        log_warn "No template files found to modify"
        return 1
    fi

    # Report findings and ask user what to do
    if [ "$original_count" -gt 0 ] && [ "$processed_count" -eq 0 ]; then
        log_info "Found $original_count template files with original format (//___FILEHEADER___)"
        echo -e "${GREEN}This appears to be a fresh Xcode installation.${NC}"
        TEMPLATE_MODE="original"
    elif [ "$original_count" -eq 0 ] && [ "$processed_count" -gt 0 ]; then
        log_warn "Found $processed_count template files with processed format (___FILEHEADER___)"
        echo -e "${YELLOW}These files appear to have been processed by this script before.${NC}"
        echo -e "${WHITE}What would you like to do?${NC}"
        echo "1. Re-process (update headers only, no file modification needed)"
        echo "2. Cancel and rollback to previous state"
        echo
        read -p "$(echo -e ${WHITE}Select option [1-2]:${NC} )" choice
        case $choice in
            1) TEMPLATE_MODE="processed" ;;
            2) log_info "Operation cancelled. Use '$0 rollback' to restore previous state."
               return 1 ;;
            *) log_error "Invalid choice. Operation cancelled."
               return 1 ;;
        esac
    else
        log_warn "Found mixed file states: $original_count original, $processed_count processed"
        echo -e "${YELLOW}This is unusual - some files appear original, others processed.${NC}"
        echo -e "${WHITE}What would you like to do?${NC}"
        echo "1. Process only original files (//___FILEHEADER___)"
        echo "2. Process all files (both formats)"
        echo "3. Cancel operation"
        echo
        read -p "$(echo -e ${WHITE}Select option [1-3]:${NC} )" choice
        case $choice in
            1) TEMPLATE_MODE="original" ;;
            2) TEMPLATE_MODE="auto" ;;
            3) log_info "Operation cancelled."
               return 1 ;;
            *) log_error "Invalid choice. Operation cancelled."
               return 1 ;;
        esac
    fi

    # Get files based on selected mode
    local -a files=()
    while IFS= read -r file; do
        [ -n "$file" ] && files+=("$file")
    done < <(find_template_files "$directory_path" "$TEMPLATE_MODE")

    if [ ${#files[@]} -eq 0 ]; then
        log_warn "No template files found for selected mode"
        return 1
    fi

    echo -e "${WHITE}Files that will be processed (${#files[@]} total):${NC}"
    printf '%s\n' "${files[@]}" | sed 's|^|  |'

    echo -e "\n${WHITE}Header template preview:${NC}"
    get_header_template "$SELECTED_TEMPLATE" | sed 's|^|  |'

    return 0
}

process_swift_files() {
    local directory_path=$1
    local backup_directory=$2
    local -a modified_files=()

    log_info "Processing Swift template files..."

    local -a files=()

    # Use the template mode determined in preview_changes
    while IFS= read -r file; do
        [ -n "$file" ] && files+=("$file")
    done < <(find_template_files "$directory_path" "${TEMPLATE_MODE:-auto}")

    if [ ${#files[@]} -eq 0 ]; then
        log_warn "No template files found to modify"
        return
    fi

    for file in "${files[@]}"; do
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would modify $file"
            continue
        fi

        # Create backup with folder structure
        local backup_file_path="$backup_directory/${file#$directory_path/}"
        mkdir -p "$(dirname "$backup_file_path")"
        cp "$file" "$backup_file_path"

        # Check first line and modify accordingly
        local first_line=$(head -n 1 "$file" 2>/dev/null)
        if [[ "$first_line" =~ ^//___FILEHEADER___ ]]; then
            # Remove "//" prefix from files that have it
            sed -i '' '1s|^//___FILEHEADER___|___FILEHEADER___|' "$file"
            log_info "Modified (removed // prefix): $file"
        else
            # File already has ___FILEHEADER___ format - no modification needed
            log_info "Processed (already correct format): $file"
        fi

        modified_files+=("$file")
    done

    # Create backup manifest
    if [ "$DRY_RUN" = false ] && [ ${#modified_files[@]} -gt 0 ]; then
        create_backup_manifest "$backup_directory" "${modified_files[@]}"
    fi

    log_success "Processed ${#modified_files[@]} Swift template files"
}

create_backup_manifest() {
    local backup_directory=$1
    shift
    local modified_files=("$@")

    local manifest_file="$backup_directory/manifest.json"

    # Build the JSON array more safely
    local json_files=""
    if [ ${#modified_files[@]} -gt 0 ]; then
        json_files="$(printf '        "%s"' "${modified_files[0]}")"
        if [ ${#modified_files[@]} -gt 1 ]; then
            json_files="$json_files$(printf ',\n        "%s"' "${modified_files[@]:1}")"
        fi
    fi

    cat > "$manifest_file" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "template_type": "$SELECTED_TEMPLATE",
    "original_directory": "$directory_path",
    "script_version": "2.0",
    "modified_files": [
$json_files
    ]
}
EOF

    log_info "Created backup manifest: $manifest_file"
}

manage_macros_file() {
    local macros_file="$HOME/Library/Developer/Xcode/UserData/IDETemplateMacros.plist"

    # Backup existing file
    if [ -f "$macros_file" ] && [ "$DRY_RUN" = false ]; then
        local backup_macros="$BACKUP_BASE_DIR/IDETemplateMacros_$(date +'%Y-%m-%d_%H-%M-%S').plist"
        cp "$macros_file" "$backup_macros"
        log_info "Backed up existing IDETemplateMacros.plist to $backup_macros"
    fi

    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would create/update IDETemplateMacros.plist"
        return
    fi

    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$macros_file")"

    # Create new macros file
    cat > "$macros_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>FILEHEADER</key>
    <string>$(get_header_template "$SELECTED_TEMPLATE")</string>
</dict>
</plist>
EOF

    log_success "Created IDETemplateMacros.plist with $SELECTED_TEMPLATE template"

    # Open the file for user review
    if command -v open &> /dev/null; then
        open "$macros_file"
    fi
}

# Rollback functionality
list_backups() {
    log_info "Available backups:"

    if [ ! -d "$BACKUP_BASE_DIR" ]; then
        log_warn "No backup directory found"
        return 1
    fi

    local -a backups=()
    while IFS= read -r -d $'\0' backup; do
        [ -n "$backup" ] && backups+=("$(basename "$backup")")
    done < <(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "*_20*" -print0 2>/dev/null | sort -z)

    if [ ${#backups[@]} -eq 0 ]; then
        log_warn "No backups found"
        return 1
    fi

    printf '%s\n' "${backups[@]}" | nl -w2 -s'. '
    return 0
}

rollback_changes() {
    if ! list_backups; then
        return 1
    fi

    echo
    read -p "$(echo -e ${WHITE}Enter backup number to restore:${NC} )" backup_num

    local -a backups=()
    while IFS= read -r -d $'\0' backup; do
        [ -n "$backup" ] && backups+=("$backup")
    done < <(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "*_20*" -print0 2>/dev/null | sort -z)

    if [ "$backup_num" -lt 1 ] || [ "$backup_num" -gt ${#backups[@]} ]; then
        handle_error "Invalid backup number"
    fi

    local selected_backup="${backups[$((backup_num-1))]}"
    local manifest_file="$selected_backup/manifest.json"

    if [ ! -f "$manifest_file" ]; then
        handle_error "Backup manifest not found. Cannot safely restore."
    fi

    log_info "Restoring from backup: $(basename "$selected_backup")"

    # Parse manifest and restore files
    local original_dir
    original_dir=$(grep '"original_directory"' "$manifest_file" | sed 's/.*: "\(.*\)",*/\1/')

    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would restore files to $original_dir"
        return
    fi

    # Restore files
    while IFS= read -r -d $'\0' backup_file; do
        local relative_path="${backup_file#$selected_backup/}"
        local original_file="$original_dir/$relative_path"

        if [ -f "$backup_file" ]; then
            cp "$backup_file" "$original_file"
            log_info "Restored: $original_file"
        fi
    done < <(find "$selected_backup" -type f -name "*.swift" -print0 2>/dev/null)

    log_success "Rollback completed successfully"
}

# Cleanup functions
clean_old_backups() {
    local days=${1:-30}

    log_info "Cleaning backups older than $days days..."

    if [ "$DRY_RUN" = true ]; then
        find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "*_20*" -mtime "+$days" -print | while read -r backup; do
            log_info "DRY RUN: Would remove $(basename "$backup")"
        done
        return
    fi

    local count=0
    find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "*_20*" -mtime "+$days" -print0 | while IFS= read -r -d $'\0' backup; do
        rm -rf "$backup"
        log_info "Removed old backup: $(basename "$backup")"
        ((count++))
    done

    log_success "Cleaned $count old backups"
}

# Main installation function
install_headers() {
    local directory_path=$1

    validate_xcode_directory "$directory_path"
    check_permissions "$directory_path"

    if ! preview_changes "$directory_path"; then
        return 1
    fi

    echo
    if [ "$DRY_RUN" = false ]; then
        read -p "$(echo -e ${WHITE}Proceed with installation? [y/N]:${NC} )" confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled by user"
            return 1
        fi
    fi

    local backup_directory
    backup_directory=$(create_backup "$directory_path")

    process_swift_files "$directory_path" "$backup_directory"
    manage_macros_file

    if [ "$DRY_RUN" = false ]; then
        log_success "Installation completed successfully"
        log_info "Backup stored at: $backup_directory"
    else
        log_info "DRY RUN completed - no changes made"
    fi
}

# Main function
main() {
    local command="install"
    local directory_path="/Applications/Xcode.app/Contents/Developer"

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            install|rollback|preview|list|clean)
                command=$1
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                log_info "DRY RUN mode enabled"
                shift
                ;;
            --template)
                SELECTED_TEMPLATE=$2
                shift 2
                ;;
            --directory)
                directory_path=$2
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    validate_environment

    # Handle non-interactive commands
    case $command in
        list)
            list_backups
            exit $?
            ;;
        clean)
            clean_old_backups
            exit 0
            ;;
        rollback)
            rollback_changes
            exit 0
            ;;
        preview)
            DRY_RUN=true
            install_headers "$directory_path"
            exit 0
            ;;
        install)
            # Check if we need sudo for the default Xcode directory
            if [[ "$directory_path" == "/Applications"* ]] && [ "$(id -u)" != 0 ]; then
                handle_error "Installation to system Xcode directory requires sudo privileges"
            fi

            # Interactive mode if no specific directory provided
            if [[ "$directory_path" == "/Applications/Xcode.app/Contents/Developer" ]]; then
                read -p "$(echo -e ${WHITE}Enter Xcode directory path [$directory_path]:${NC} )" input_path
                directory_path="${input_path:-$directory_path}"
            fi

            select_header_template
            install_headers "$directory_path"
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
