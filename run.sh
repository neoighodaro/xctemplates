#!/bin/bash

# Styling
WHITE='\033[1;37m'
NC='\033[0m' # No Color
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'

# Check if script is run with sudo
if [ "$(id -u)" != 0 ]; then
    echo -e "${YELLOW}==> Warning: ${NC}This script must be run with superuser privileges. Please use 'sudo'."
    exit 1
fi

# Set default directory path
default_directory="/Applications/Xcode.app/Contents/Developer"

# Get the supplied directory from input with color
read -p "$(echo -e ${WHITE}Enter the directory path [$default_directory]:${NC} )" directory_path
directory_path="${directory_path:-$default_directory}"

# Check if directory exists
if [ ! -d "$directory_path" ]; then
    echo -e "${RED}==> Error: Directory does not exist. Please enter a valid directory path.${NC}"
    exit 1
fi

# Extract directory name
directory_name=$(basename "$directory_path")

# Create backup directory with current date and time
echo -e "${WHITE}==> Creating backup directory...${NC}"
backup_directory=~/xctemplates_backup/"$directory_name"_"$(date +'%Y-%m-%d_%H-%M-%S')"
mkdir -p "$backup_directory"
echo -e "${GREEN}==> Backup directory created at $backup_directory${NC}"

# Create a backup json array file
backup_json="$backup_directory/modified_files.json"
echo "[" > "$backup_json"

# Process .swift files
echo -e "${WHITE}==> Processing .swift template files${NC}"
find "$directory_path" -type f -name "*.swift" -print0 | while IFS= read -r -d $'\0' file; do
    # Check if file starts with //___FILEHEADER___
    if head -n 1 "$file" | grep -q "//___FILEHEADER___"; then
        # Append file path to the backup json array
        echo "\"$file\"," >> "$backup_json"

        # Backup the file with folder structure
        backup_file_path="$backup_directory/${file#$directory_path/}"
        mkdir -p "$(dirname "$backup_file_path")"
        cp "$file" "$backup_file_path"

        # Remove "//" prefix from the file
        # We do this because we intend to use FILEHEADER as the store for the entire header
        # so we can use whatever comment style we want when we remove the prefix
        sed -i '' '1s|^//___FILEHEADER___|___FILEHEADER___|' "$file"
    fi
done

echo "\"\"]" >> "$backup_json"
echo -e "${GREEN}==> .swift template files processed successfully${NC}"

# Backup IDETemplateMacros.plist if it exists
macros_file=~/Library/Developer/Xcode/UserData/IDETemplateMacros.plist
if [ -f "$macros_file" ]; then
    echo -e "${WHITE}==> Existing IDETemplateMacros.plist found backing up...${NC}"
    cp "$macros_file" ~/xctemplates_backup/IDETemplateMacros_"$(date +'%Y-%m-%d_%H-%M-%S')".plist
fi

# Create a new IDETemplateMacros.plist
echo -e "${WHITE}==> Creating new global IDETemplateMacros.plist...${NC}"
cat > $macros_file << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>FILEHEADER</key>
	<string>
/**
 * ___PRODUCTNAME___
 *
 * Copyright © ___YEAR___ ___ORGANIZATIONNAME___. All rights reserved.
 *
 * Unauthorized copying of this file, via any medium is strictly prohibited.
 * Proprietary and confidential.
 *
 * @author ___FULLUSERNAME___
 */
 </string>
</dict>
</plist>
EOL

echo -e "${GREEN}==> IDETemplateMacros.plist created successfully. Opening it...${NC}"
open ~/Library/Developer/Xcode/UserData/IDETemplateMacros.plist

echo -e "${WHITE}==> Backup files are stored in $backup_directory${NC}"
echo -e "${GREEN}==> Script completed successfully.${NC}"
exit 0
