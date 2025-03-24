#!/bin/bash
# Usage: ./remove_driver_deps.sh [directory]
# If no directory is provided, the script uses the current directory.

# Use the provided directory or default to the current directory.
dir="${1:-.}"

# Enable nullglob so that non-matching globs expand to nothing.
shopt -s nullglob

# Create an array to hold the package names.
packages=()

# Loop through all .rpm files in the specified directory.
for file in "$dir"/*.rpm; do
    # Extract the package name (basename without .rpm).
    pkg=$(basename "$file" .rpm)
    packages+=("$pkg")
done

# Check if the array is empty.
if [ ${#packages[@]} -eq 0 ]; then
    echo "No RPM packages found in '$dir'."
    exit 0
fi

# Display the packages to be removed.
echo "Removing the following packages from '$dir':"
printf '  %s\n' "${packages[@]}"

# Proceed to remove the packages.
sudo dnf remove --noautoremove "${packages[@]}"
