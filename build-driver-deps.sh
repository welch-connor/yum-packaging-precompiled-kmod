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

# create folder for full NVIDIA package, including dependencies
mkdir $topdir/repo_${module}/full_nvidia_${module}_package -p
cd $topdir/repo_${module}/full_nvidia_${module}_package

# copy `repo_${module}` directory
cp -f "$topdir/repo_${module}"/*.rpm .

# recursively download all deps
sudo dnf download --resolve "$topdir/repo_${module}/full_nvidia_${module}_package"/*.rpm 

# Zip up repo for transfer
echo "Zipping directory '"$topdir/repo_${module}/full_nvidia_${module}_package..."'"
tar -czvf nvidia-driver-${module}.tar.gz -C "$topdir/repo_${module}" full_nvidia_${module}_package