#!/usr/bin/env bash

# Set environment variables
# `topdir` is directory above `repo_${module}`
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
mkdir $topdir/repo_${module}/nvidia-driver-${module} -p
cd $topdir/repo_${module}/nvidia-driver-${module}

# copy `repo_${module}` directory
cp -f "$topdir/repo_${module}"/*.rpm .

# recursively download all deps
sudo dnf download --resolve "$topdir/repo_${module}/nvidia-driver-${module}"/*.rpm 

# Zip up repo for transfer
echo "Zipping directory '"$topdir/repo_${module}/nvidia-driver-${module}..."'"
tar -czvf nvidia-driver-${module}.tar.gz -C "$topdir/repo_${module}" nvidia-driver-${module}

# move driver gzip to $topdir
echo "Moving nvidia-driver-${module}.tar.gz from: $topdir/repo_${module}/nvidia-driver-${module}/ -> $topdir"
cp "$topdir/repo_${module}/nvidia-driver-${module}/nvidia-driver-${module}.tar.gz" $topdir
rm -f "$topdir/repo_${module}/nvidia-driver-${module}/nvidia-driver-${module}.tar.gz"
echo "Driver package complete; saved at: $topdir/nvidia-driver-${module}.tar.gz"