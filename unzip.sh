#!/bin/bash

# Check for valid arguments
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [password]"
    exit 1
fi

PASSWORD="${1:-}"
FIND_DIR="."  # Starting directory

# Install required utilities
install_deps() {
    if ! command -v unzip &> /dev/null; then
        echo "Installing unzip..."
        sudo apt-get update && sudo apt-get install -y unzip
    fi
    
    if ! command -v 7z &> /dev/null; then
        echo "Installing p7zip-full..."
        sudo apt-get update && sudo apt-get install -y p7zip-full
    fi
}

# Handle ZIP archives
process_zip() {
    find "$FIND_DIR" -type f -name "*.zip" | while read -r archive; do
        echo "Processing ZIP: $archive"
        target="${archive%.zip}"
        mkdir -p "$target"

        unzip_args=(-o -d "$target" "$archive")
        [ -n "$PASSWORD" ] && unzip_args=(-P "$PASSWORD" "${unzip_args[@]}")

        if unzip "${unzip_args[@]}"; then
            echo "✓ Extracted: $archive"
            rm -f "$archive"
        else
            echo "✗ Failed: $archive (password required?)"
        fi
        echo "------------------------"
    done
}

# Handle 7z archives with improved password handling
process_7z() {
    find "$FIND_DIR" -type f \( -name "*.7z" -o -name "*.7z.001" \) | while read -r archive; do
        echo "Processing 7z: $archive"
        target="${archive%.7z*}"
        mkdir -p "$target"

        sevenz_args=(x -o"$target" "$archive" -y)
        [ -n "$PASSWORD" ] && sevenz_args=(-p"$PASSWORD" "${sevenz_args[@]}")

        # Use 7z with full error reporting
        if 7z "${sevenz_args[@]}" -bse1; then
            echo "✓ Extracted: $archive"
            rm -f "$archive"
        else
            echo "✗ Failed: $archive (password error or corrupt file)"
            echo "Note for 7z files:"
            echo "1. Ensure password is correct for AES-256 encrypted archives"
            echo "2. Verify file integrity with '7z t -p\"PASSWORD\" ARCHIVE.7z'"
            echo "3. Check for multi-volume archives (.7z.001, .7z.002, etc)"
        fi
        echo "------------------------"
    done
}

# Main execution
install_deps
process_zip
process_7z

echo "Processing complete. Successful extractions were cleaned."