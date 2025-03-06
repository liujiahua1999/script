#!/bin/bash

# Script to reassign metadata based on folder structure
# Usage: ./reassign_metadata.sh [directory]

# Default directory is current directory
directory=${1:-.}

# Check if required tools are installed
check_requirements() {
    # Check for ExifTool
    if ! command -v exiftool &> /dev/null; then
        echo "Error: ExifTool is not installed"
        echo "Please install with: brew install exiftool"
        exit 1
    fi
    
    # Check for FFmpeg (for video/audio)
    if ! command -v ffmpeg &> /dev/null; then
        echo "Error: FFmpeg is not installed"
        echo "Please install with: brew install ffmpeg"
        exit 1
    fi
}

# Function to identify file type
get_file_type() {
    local file="$1"
    local ext=$(echo "${file##*.}" | tr '[:upper:]' '[:lower:]')
    
    case "$ext" in
        # Image files
        jpg|jpeg|png|gif|bmp|tiff|tif|heic|webp)
            echo "image"
            ;;
        # Video files
        mp4|mov|avi|mkv|wmv|flv|webm|m4v)
            echo "video"
            ;;
        # Audio files
        mp3|wav|aac|flac|ogg|m4a|wma)
            echo "audio"
            ;;
        # Other files
        *)
            echo "unknown"
            ;;
    esac
}

# Generate a unique date based on album name
generate_unique_date() {
    local album_name="$1"
    local artist_name="$2"
    
    # Create a hash string based on album and artist names
    local hash_input="$artist_name-$album_name"
    
    # Use the first 8 characters of the MD5 hash as a pseudo-random seed
    local hash_value=$(echo "$hash_input" | md5)
    local seed=$(echo "$hash_value" | cut -c1-8)
    
    # Convert hex seed to numeric
    # Since older bash may not support 0x prefix, we'll use a simpler approach
    local num=0
    for ((i=0; i<${#seed}; i++)); do
        char="${seed:$i:1}"
        case "$char" in
            [0-9]) val=$char ;;
            a) val=10 ;;
            b) val=11 ;;
            c) val=12 ;;
            d) val=13 ;;
            e) val=14 ;;
            f) val=15 ;;
        esac
        num=$((num * 16 + val))
    done
    
    # Calculate date components
    local base_year=2010
    local year_offset=$((num % 10))
    local year=$((base_year + year_offset))
    local month=$(( (num % 12) + 1 ))
    local day=$(( (num % 28) + 1 ))  # Limiting to 28 to avoid month boundary issues
    local hour=$(( num % 24 ))
    local minute=$(( (num % 60) ))
    local second=$(( (num % 60) ))
    
    # Format the date as YYYY:MM:DD HH:MM:SS
    printf "%04d:%02d:%02d %02d:%02d:%02d" $year $month $day $hour $minute $second
}

# Set metadata for image files using ExifTool
set_image_metadata() {
    local file="$1"
    local artist="$2"
    local album="$3"
    local creation_date="$4"
    
    echo "Setting metadata for image: $file"
    
    # Set artist, album, and creation date
    exiftool -overwrite_original \
        -Artist="$artist" \
        -CreatorContactInfo="$artist" \
        -By-line="$artist" \
        -Credit="$artist" \
        -AlbumLabel="$album" \
        -Album="$album" \
        -ImageDescription="$album" \
        -DateTimeOriginal="$creation_date" \
        -CreateDate="$creation_date" \
        -ModifyDate="$creation_date" \
        "$file" > /dev/null 2>&1
    
    echo "  ✓ Metadata set"
}

# Set metadata for video files
set_video_metadata() {
    local file="$1"
    local artist="$2"
    local album="$3"
    local creation_date="$4"
    local temp_file="${file}.temp.mp4"
    
    echo "Setting metadata for video: $file"
    
    # First remove all existing metadata
    ffmpeg -i "$file" -map_metadata -1 -c:v copy -c:a copy -y "$temp_file" 2>/dev/null
    
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        mv "$temp_file" "$file"
        
        # Now add our metadata using ExifTool
        exiftool -overwrite_original \
            -Artist="$artist" \
            -Author="$artist" \
            -Album="$album" \
            -Title="$album" \
            -CreateDate="$creation_date" \
            -ModifyDate="$creation_date" \
            -MediaCreateDate="$creation_date" \
            -MediaModifyDate="$creation_date" \
            -TrackCreateDate="$creation_date" \
            -TrackModifyDate="$creation_date" \
            "$file" > /dev/null 2>&1
        
        echo "  ✓ Metadata set"
    else
        echo "  ✗ Failed to set metadata"
        # Clean up temp file if it exists
        [ -f "$temp_file" ] && rm "$temp_file"
    fi
}

# Set metadata for audio files
set_audio_metadata() {
    local file="$1"
    local artist="$2"
    local album="$3"
    local creation_date="$4"
    
    echo "Setting metadata for audio: $file"
    
    # For audio, we'll use ExifTool directly
    exiftool -overwrite_original \
        -Artist="$artist" \
        -Author="$artist" \
        -AlbumArtist="$artist" \
        -Album="$album" \
        -Title="$album" \
        -Year="${creation_date:0:4}" \
        -CreateDate="$creation_date" \
        -ModifyDate="$creation_date" \
        "$file" > /dev/null 2>&1
    
    echo "  ✓ Metadata set"
}

# Store processed albums to ensure unique dates
process_album() {
    local album_dir="$1"
    local parent_dir=$(dirname "$album_dir")
    local artist=$(basename "$parent_dir")
    local album=$(basename "$album_dir")
    
    # Skip if this doesn't look like an album (parent is the base directory)
    if [ "$parent_dir" = "$directory" ]; then
        return
    fi
    
    # Check if this folder contains media files
    local has_media=0
    for file in "$album_dir"/*; do
        if [ -f "$file" ]; then
            file_type=$(get_file_type "$file")
            if [ "$file_type" != "unknown" ]; then
                has_media=1
                break
            fi
        fi
    done
    
    if [ $has_media -eq 1 ]; then
        echo "Processing album: $artist - $album"
        
        # Generate unique date for this album
        creation_date=$(generate_unique_date "$album" "$artist")
        echo "  Using creation date: $creation_date"
        
        # Process all files in this directory
        for file in "$album_dir"/*; do
            if [ -f "$file" ]; then
                # Skip hidden files and temporary files
                filename=$(basename "$file")
                if [[ "$filename" == .* || "$filename" == *.temp.* ]]; then
                    continue
                fi
                
                # Get file type
                file_type=$(get_file_type "$file")
                
                case "$file_type" in
                    image)
                        set_image_metadata "$file" "$artist" "$album" "$creation_date"
                        ;;
                    video)
                        set_video_metadata "$file" "$artist" "$album" "$creation_date"
                        ;;
                    audio)
                        set_audio_metadata "$file" "$artist" "$album" "$creation_date"
                        ;;
                    unknown)
                        echo "Skipping unknown file type: $file"
                        ;;
                esac
            fi
        done
        
        echo "  ✓ Completed album metadata assignment"
    fi
}

# Process all directories
process_directories() {
    local base_dir="$1"
    
    echo "Scanning directory structure: $base_dir"
    
    # Keep track of processed album dates in a file
    processed_albums_file=$(mktemp)
    
    # Use find to locate all directories and process them one by one
    find "$base_dir" -type d | while read -r dir; do
        # Skip the base directory
        if [ "$dir" = "$base_dir" ]; then
            continue
        fi
        
        # Process this as a potential album
        process_album "$dir"
    done
    
    # Clean up
    rm -f "$processed_albums_file"
}

# Main function
main() {
    echo "=== Media Metadata Assignment Tool ==="
    
    # Check for required tools
    check_requirements
    
    # Process the specified directory
    process_directories "$directory"
    
    echo "=== Completed ==="
}

# Run the main function
main