#!/bin/bash

# Check if script is run with sudo
if [ "$(id -u)" != 0 ]; then
    echo "This script must be run with superuser privileges. Please use 'sudo'."
    exit 1
fi

# Set default directory path
default_directory="/Applications/Xcode-beta.app/Contents/Developer"

# Get the supplied directory from input
read -p "Enter the directory path [$default_directory]: " directory_path
directory_path="${directory_path:-$default_directory}"

# Extract directory name
directory_name=$(basename "$directory_path")

# Create backup directory with current date and time
backup_directory=~/xctemplates_backup/"$directory_name"_"$(date +'%Y-%m-%d_%H-%M-%S')"
mkdir -p "$backup_directory"

# Create a backup json array file
backup_json="$backup_directory/modified_files.json"
echo "[" > "$backup_json"

# Recursively look for .swift files with // ___FILEHEADER___
TEMPLATE_FILES=$(find "$directory_path" -type f -name "*.swift" -exec grep -l "^// ___FILEHEADER___" {} \;)

# Process .swift files
find "$directory_path" -type f -name "*.swift" -print0 | while IFS= read -r -d $'\0' file; do
    # Check if file starts with //___FILEHEADER___
    if head -n 1 "$file" | grep -q "//___FILEHEADER___"; then
        # Append file path to the backup json array
        echo "\"$file\"," >> "$backup_json"

        # Backup the file with folder structure
        backup_file_path="$backup_directory/${file#$directory_path/}"
        mkdir -p "$(dirname "$backup_file_path")"
        cp "$file" "$backup_file_path"

        # Remove "//" from the file
        sed -i '' '1s|^// ___FILEHEADER___|___FILEHEADER___|' "$file"
    fi
done

echo "\"\"]" >> "$backup_json"

# Backup IDETemplateMacros.plist if it exists
macros_file=~/Library/Developer/Xcode/UserData/IDETemplateMacros.plist
if [ -f "$macros_file" ]; then
    cp "$macros_file" ~/xctemplates_backup/IDETemplateMacros_"$(date +'%Y-%m-%d_%H-%M-%S')".plist
fi

# Create a new IDETemplateMacros.plist
cat > ~/Library/Developer/Xcode/UserData/IDETemplateMacros.plist << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>FILEHEADER</key>
    <string>/**
 * Copyright © [[COMPANY]] - All Rights Reserved
 *
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by [[AUTHOR]] &lt;[[EMAIL]]&gt;, 2023
 */</string>
</dict>
</plist>
EOL

echo "You should update FILEHEADER macro in IDETemplateMacros.plist with your own details."
open ~/Library/Developer/Xcode/UserData/IDETemplateMacros.plist

echo "Backup files are stored in $backup_directory"
echo "Script completed successfully."
exit 0
