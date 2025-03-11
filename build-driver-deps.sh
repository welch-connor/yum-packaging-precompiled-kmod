#!/usr/bin/env bash

# Set environment variables
topdir="${1:-~}"
module="${2:-565}"

cd $topdir/repo_${module}

# Enable nullglob so that non-matching globs expand to nothing.
shopt -s nullglob

# Create an array to hold the package names.
packages=()

# Loop through all .rpm files in the specified directory.
for file in "$topdir/repo_${module}"/*.rpm; do
    # Extract the package name (basename without .rpm).
    pkg=$(basename "$file" .rpm)
    packages+=("$pkg")
done

# Check if the array is empty.
if [ ${#packages[@]} -eq 0 ]; then
    echo "No RPM packages found in '$topdir'."
    exit 0
fi

# Display the packages to have added dependencies.
echo "Adding dependencies for packages from '"$topdir/repo_${module}"':"
printf '  %s\n' "${packages[@]}"

mkdir $topdir/repo_${module}/deps -p
cd $topdir/repo_${module}/deps
# Loop through each package and download dependencies individually into /deps directory
for pkg in "${packages[@]}"; do
    echo "Downloading dependencies for: $pkg in '"$topdir/repo_${module}"'"
    sudo dnf download --resolve "$topdir/repo_${module}/$pkg.rpm" || echo "Failed to download dependencies for $pkg, skipping..."
done

# Zip up repo for transfer
echo "Zipping directory '"$topdir/repo_${module}/deps..."'"
tar -czvf nvidia-driver-${module}.tar.gz -C "$topdir/repo_${module}/deps"