#!/bin/bash

# Script to rename pictures and folders, removing patterns like [31P4V-1.63GB]
# Usage: ./rename_pictures_and_folders.sh [directory]

# Default directory is current directory
directory=${1:-.}

# Function to check if a file is an image based on extension
is_image() {
    local file="$1"
    local ext=$(echo "${file##*.}" | tr '[:upper:]' '[:lower:]')
    
    case "$ext" in
        jpg|jpeg|png|gif|bmp|tiff|webp|tif|heic)
            return 0  # True, is an image
            ;;
        *)
            return 1  # False, not an image
            ;;
    esac
}

# Function to clean name by removing various patterns like "[31P4V-1.63GB]", "[334P 80M]", etc.
clean_name() {
    local name="$1"
    
    # Step 1: Remove patterns with brackets [...]
    # This handles patterns like:
    # [31P4V-1.63GB]
    # [20P-168MB]
    # [334P 80M]
    # [高清大图]
    cleaned_name=$(echo "$name" | sed -E 's/\[[^]]*\]//g')
    
    # Step 2: Trim multiple spaces to single space
    cleaned_name=$(echo "$cleaned_name" | sed -E 's/[[:space:]]+/ /g')
    
    # Step 3: Trim leading and trailing spaces
    cleaned_name=$(echo "$cleaned_name" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
    
    echo "$cleaned_name"
}

# Process folders recursively (from deepest to root to avoid path issues)
echo "First pass: Renaming folders..."
find "$directory" -type d -depth | while read -r dir; do
    # Skip the root directory itself
    if [ "$dir" = "$directory" ]; then
        continue
    fi
    
    # Get folder name and clean it
    folder_name=$(basename "$dir")
    cleaned_folder_name=$(clean_name "$folder_name")
    
    # Skip if the folder name is already clean
    if [ "$folder_name" = "$cleaned_folder_name" ]; then
        continue
    fi
    
    # Get parent directory
    parent_dir=$(dirname "$dir")
    new_dir_path="$parent_dir/$cleaned_folder_name"
    
    # Rename the folder if the new name is different and doesn't already exist
    if [ "$dir" != "$new_dir_path" ] && [ ! -d "$new_dir_path" ]; then
        echo "Renaming folder: $folder_name → $cleaned_folder_name"
        mv "$dir" "$new_dir_path"
    elif [ -d "$new_dir_path" ] && [ "$dir" != "$new_dir_path" ]; then
        echo "Warning: Cannot rename $folder_name → $cleaned_folder_name (destination already exists)"
    fi
done

# Process folders recursively to rename pictures
echo "Second pass: Renaming pictures..."
process_folder() {
    local current_dir="$1"
    
    # Use find to get all directories
    find "$current_dir" -type d | while read -r dir; do
        # Skip the root directory itself
        if [ "$dir" = "$current_dir" ]; then
            continue
        fi
        
        # Get folder name (should be already clean from first pass)
        folder_name=$(basename "$dir")
        
        echo "Processing folder: $folder_name"
        
        # Create a temporary array of image files
        cd "$dir" || continue
        
        # Get all files, then filter for images
        image_files=()
        for file in *; do
            # Skip if not a regular file
            [ -f "$file" ] || continue
            
            if is_image "$file"; then
                image_files+=("$file")
            fi
        done
        
        # Count total images found in this directory
        total=${#image_files[@]}
        echo "Found $total image files in $folder_name"
        
        if [ $total -eq 0 ]; then
            echo "No image files found in $folder_name. Skipping."
            cd - > /dev/null
            continue
        fi
        
        # Sort the files naturally
        temp_file=$(mktemp)
        for f in "${image_files[@]}"; do
            echo "$f" >> "$temp_file"
        done
        
        # Read sorted files back
        sorted_files=()
        while IFS= read -r line; do
            sorted_files+=("$line")
        done < <(sort "$temp_file")
        
        # Clean up
        rm -f "$temp_file"
        
        # Start renaming
        count=1
        for original in "${sorted_files[@]}"; do
            # Skip if the file doesn't exist (in case it was already renamed)
            [ -f "$original" ] || continue
            
            # Get file extension
            ext="${original##*.}"
            
            # Create new filename with folder name
            new_name="$folder_name - $count.$ext"
            
            # Rename the file if it's not already named correctly
            if [ "$original" != "$new_name" ]; then
                mv "$original" "$new_name"
                echo "Renamed: $original → $new_name"
            else
                echo "Skipped: $original (already has the correct name)"
            fi
            
            count=$((count + 1))
        done
        
        # Go back to the original directory
        cd - > /dev/null
        
        echo "Completed renaming in $folder_name"
        echo "-----------------------------------"
    done
}

# Start processing
process_folder "$directory"
echo "All done!"