#!/bin/bash

# Navigate to the script's directory (essential for .command files)
cd "$(dirname "$0")"

# Prompt for version input
read -p "Enter version number (e.g., 1.0.2): " VERSION

if [ -z "$VERSION" ]; then
    echo "Error: Version cannot be empty."
    exit 1
fi

ADDON_NAME="MiliUI_ChatBar"
ZIP_NAME="${ADDON_NAME}_v${VERSION}.zip"
BUILD_DIR="/tmp/${ADDON_NAME}_Build"

# Clean up any previous build dir
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$ADDON_NAME"

echo "Preparing build for version $VERSION..."

# Copy files to temp build directory (excluding unwanted files)
# Using rsync for better exclusion handling
rsync -av --exclude='.*' \
      --exclude='package.command' \
      --exclude='package.sh' \
      --exclude='*.zip' \
      --exclude='__MACOSX' \
      . "$BUILD_DIR/$ADDON_NAME" > /dev/null

# Replace placeholder {version} with actual version in TOC
TOC_FILE="$BUILD_DIR/$ADDON_NAME/${ADDON_NAME}.toc"
if [ -f "$TOC_FILE" ]; then
    # Use sed to replace {version} with the input version
    # The '' argument is needed for macOS sed compatibility
    sed -i '' "s/{version}/$VERSION/g" "$TOC_FILE"
    echo "Updated TOC version to $VERSION in build."
else
    echo "Error: TOC file not found at $TOC_FILE"
    exit 1
fi

# Create the zip file from the build directory
CURRENT_DIR=$(pwd)
cd "$BUILD_DIR"

echo "Creating zip archive..."
zip -r -X "$CURRENT_DIR/$ZIP_NAME" "$ADDON_NAME" > /dev/null

if [ $? -eq 0 ]; then
    echo "Success! Archive created at:"
    echo "$CURRENT_DIR/$ZIP_NAME"
else
    echo "Error: Failed to create zip archive."
    exit 1
fi

# Cleanup
cd "$CURRENT_DIR"
rm -rf "$BUILD_DIR"

# Wait for user input before closing (so they can see the result)
echo ""
read -n 1 -s -r -p "Press any key to close..."
