#!/usr/bin/env bash

## Revised NVIDIA pre-compiled driver script; source: https://github.com/NVIDIA/yum-packaging-precompiled-kmod/blob/main/build.sh

# Argument inputs
runfile="$1"
distro="$2"
module="$3"

# Build defaults
topdir=~
stream="latest"
epoch=3

[[ -n $distro ]] ||
distro=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[[ $distro == "main" ]] && distro="rhel8"

drvname=$(basename "$runfile")
arch=$(echo "$drvname" | awk -F "-" '{print $3}')
[[ -n $arch ]] || arch="x86_64"
version=$(echo "$drvname" | sed -e "s|NVIDIA\-Linux\-${arch}\-||" -e 's|\.run$||' -e 's|\-grid$||' -e 's|\.tar\..*||' -e 's|nvidia\-settings\-||')
drvbranch=$(echo "$version" | awk -F "." '{print $1}')

# Driver defaults
tarball=nvidia-kmod-${version}-${arch}
unpackDir="unpack"

err() { echo; echo "ERROR: $*"; exit 1; }
kmd() { echo; echo ">>> $*" | fold -s; eval "$*" || err "at line \`$*\`"; }
dep() { type -p "$1" >/dev/null || err "missing dependency $1"; }
get_gpgkey() { gpgKey=$(gpg --list-secret-keys --with-colons | grep "^sec" | sort -t: -k 5 -r | grep -o -E "[A-Z0-9]{8,}" | grep "[0-9]" | grep "[A-Z]" | grep -oE "[0-9A-Z]{8}$"); }


# X.509 defaults
userName=$USER
userEmail=$(git config --get user.email)
configFile="x509-configuration.ini"
privateKey="private_key.priv"
publicKey="public_key.der"

# GPG defaults
gpgBin=$(type -p gpg)
gpgConfig="gpg.cfg"
gpgKey=""
[[ $gpgKey ]] || get_gpgkey
gpgArgs="$gpgBin --force-v3-sigs --digest-algo=sha512  --no-verbose --no-armor --no-secmem-warning"

# Kernel defaults
kernel=$(uname -r | awk -F '-' '{print $1}')
release=$(uname -r | awk -F '-' '{print $2}' | sed -r 's|\.[a-z]{2}[0-9]+| |' | awk '{print $1}')
dist=$(uname -r | awk -F '-' '{print $2}' | sed -r -e 's|\.[a-z]{2}[0-9]+| &|' -e "s|\.${arch}||" | awk '{print $2}')

# CUDA defaults
baseURL="http://developer.download.nvidia.com/compute/cuda/repos"
downloads=$topdir/repo

# Repo defaults
myRepo="nvidia-precompiled-${distro}-${version}"
repoFile="${myRepo}.repo"


#
# Functions
#

clean_up() {
    rm -rf "$unpackDir"
    rm -rf nvidia-kmod-*-${arch}
    rm -vf nvidia-kmod-*-${arch}.tar.xz
    rm -vf primary.xml
    rm -vf modules.yaml
    rm -vf $configFile
    rm -vf $gpgConfig
    rm -vf $repoFile
    exit 1
}

git_ignore() {
    cat >.gitignore <<-EOF
	gpg.cfg
	modules.yaml
	my-precompiled.repo
	nvidia-kmod*.tar.xz
	primary.xml
	private_key.priv
	public_key.der
	x509-configuration.ini
EOF
}

generate_tarballs()
{
    mkdir "${tarball}"
    sh "${runfile}" --extract-only --target ${unpackDir}
    mv "${unpackDir}/kernel" "${tarball}/"
    rm -rf ${unpackDir}
    tar --remove-files -cJf "${tarball}.tar.xz" "${tarball}"
}

new_cert_config()
{
    [[ $userName ]] || err "Missing \$userName"
    [[ $userEmail ]] || err "Missing \$userEmail"
    echo ":: userName: $userName"
    echo ":: userEmail: $userEmail"

    # Configuration for X.509 certificate
    cat > $configFile <<-EOF
	[ req ]
	default_bits = 4096
	distinguished_name = req_distinguished_name
	prompt = no
	string_mask = utf8only
	x509_extensions = myexts

	[ req_distinguished_name ]
	O = $userName
	CN = $userName
	emailAddress = $userEmail

	[ myexts ]
	basicConstraints=critical,CA:FALSE
	keyUsage=digitalSignature
	subjectKeyIdentifier=hash
	authorityKeyIdentifier=keyid
EOF
}

new_certificate()
{
    if [[ -f "$configFile" ]]; then
        echo ":: using $configFile"
    else
        echo "  -> new_cert_config()"
        new_cert_config
    fi

    # Generate X.509 certificate
    kmd openssl req -x509 -new -nodes -utf8 -sha256 -days 36500 -batch -config $configFile \
      -outform DER -out $publicKey -keyout $privateKey
}

new_gpgkey()
{
    cat >$gpgConfig <<-EOF
	Key-Type: RSA
	Key-Length: 4096
	Name-Real: $userName
	Name-Email: $userEmail
	Expire-Date: 0
EOF

    kmd gpg --batch --generate-key $gpgConfig
    get_gpgkey
}

kmod_rpm()
{
    (cd "$topdir" && mkdir BUILD BUILDROOT RPMS SRPMS SOURCES SPECS)

    cp -v -- *key* "$topdir/SOURCES/"
    cp -v -- *tar* "$topdir/SOURCES/"
    cp -v -- *.spec "$topdir/SPECS/"
    cd "$topdir" || err "Unable to cd into $topdir"

    if [[ ${distro,,} =~ "fedora" ]]; then
        echo ":: export IGNORE_CC_MISMATCH=1"
        export IGNORE_CC_MISMATCH=1
    fi

    kmd rpmbuild \
        --define "'%_topdir $(pwd)'" \
        --define "'debug_package %{nil}'" \
        --define "'kernel $kernel'" \
        --define "'kernel_release $release'" \
        --define "'kernel_dist $dist'" \
        --define "'driver $version'" \
        --define "'epoch $epoch'" \
        --define "'driver_branch $stream'" \
        -v -bb SPECS/kmod-nvidia.spec

    cd - || err "Unable to cd into $OLDPWD"
}

sign_rpm()
{
    signature=$(rpm -qip "$1" | grep ^Signature)
    [[ $signature =~ "none" ]] || return

    kmd rpm \
        --define "'%_signature gpg'" \
        --define "'%_gpg_name $gpgKey'" \
        --define "'%__gpg $gpgBin'" \
        --define "'%_gpg_digest_algo sha512'" \
        --define "'%_binary_filedigest_algorithm 10'" \
        --define "'%__gpg_sign_cmd %{__gpg} $gpgArgs -u %{_gpg_name} -sbo %{__signature_filename} %{__plaintext_filename}'" \
        --addsign "$1"
}

copy_rpms()
{
    repoMD=$(curl -sL ${baseURL}/${distro}/${arch}/repodata/repomd.xml)
    gzipPath=$(echo "$repoMD" | grep primary\.xml | awk -F '"' '{print $2}')
    echo ":: $gzipPath"

    rm -f primary.xml
    curl -sL "${baseURL}/${distro}/${arch}/${gzipPath}" --output primary.xml.gz
    gunzip primary.xml.gz

    plugin=$(grep -E "plugin-nvidia" primary.xml | grep "<location" | awk -F '"' '{print $2}' | sort -rV | awk NR==1)
    driverFiles=$(grep -E "${version}-" primary.xml | grep "<location" | awk -F '"' '{print $2}')
    eglx11=$(grep -E "egl-x11" primary.xml | grep "<location" | grep -E "${arch}" | awk -F '"' '{print $2}' | sort -rV | awk NR==1)
    eglwayland=$(grep -E "\<egl-wayland-[^a-zA-Z]" primary.xml | grep "<location" | grep -E "${arch}" | awk -F '"' '{print $2}' | sort -rV | awk 'NR==1')
    eglwaylandDevel=$(grep -E "egl-wayland-devel" primary.xml | grep "<location" | grep -E "${arch}" | awk -F '"' '{print $2}' | sort -rV | awk NR==1)

    if [[ -z "$driverFiles" ]]; then
        err "Unable to locate $version driver packages in repository for ${distro}/${arch}"
    fi

    if [[ $distro == "rhel7" ]]; then
        plugin=$(grep -E "plugin-nvidia" primary.xml | grep "<location" | awk -F '"' '{print $2}' | sort -rV | awk NR==1)
        glvndFiles=$(grep -E "libglvnd" primary.xml | grep "<location" | awk -F '"' '{print $2}' | sort -rV | awk NR==1)
        if [[ $stream == "latest" ]]; then
            driverFiles=$(grep -E "${version}-" primary.xml | grep "<location" | awk -F '"' '{print $2}' | grep -E -v -e "latest-dkms" -e "branch")
        elif [[ $stream =~ "branch" ]]; then
            driverFiles=$(grep -E "${version}-" primary.xml | grep "<location" | awk -F '"' '{print $2}' | grep -E -v "latest")
        fi
    fi

    mkdir -p "$downloads"

    # Rest of driver packages
    for rpm in $plugin $glvndFiles $driverFiles $eglx11 $eglwayland $eglwaylandDevel; do
        echo "  -> $rpm"
        if [[ ! -f ${downloads}/${rpm} ]]; then
            curl -sL "${baseURL}/${distro}/${arch}/${rpm}" --output "${downloads}/${rpm}"
        fi
    done

    # downloads `binutils` depedency to enable usage of `kmod-nvidia` package
    sudo dnf download --downloaddir="${downloads}/${rpm}" binutils
}

make_repo()
{
    cd "$topdir"
    # genmodules.py
    if [[ ! -f genmodules.py ]]; then
        echo "Unable to locate genmodules.py; downloading from GitHub..."
        curl -O https://raw.githubusercontent.com/NVIDIA/cuda-repo-management/main/genmodules.py
        chmod +x genmodules.py
    fi

    # kmod packages
    for rpm in "$topdir/RPMS/${arch}"/*.rpm; do
        cp -v "$rpm" "$downloads/"
    done

    #cd $downloads

    if [[ $distro == "rhel7" ]]; then
        createrepo -v --database "$downloads" || err "createrepo"
    else
        createrepo_c -v --database "$downloads" || err "createrepo_c"
        python3 ./genmodules.py "$downloads" modules.yaml || err "genmodules.py"
        modifyrepo_c modules.yaml "$downloads/repodata" || err "modifyrepo_c"
    fi
}

repo_file()
{
    cat >$repoFile <<-EOF
	[$myRepo]
	name=$myRepo
	baseurl=file://${topdir}/repo
	enabled=1
	gpgcheck=0
EOF
    echo "  -> $repoFile"
}

select_module()
{
    # installing yq
    if [[ ! -f yq_linux_amd64 ]]; then
        echo "Unable to locate yq_linux_amd64; downloading from GitHub and installing to /usr/bin..."
        curl -OL https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_amd64
        sudo mv yq_linux_amd64 /usr/bin/yq
        sudo chmod +x /usr/bin/yq
    fi
    
    cd "$topdir"
    if [[ ! -f modules.yaml ]]; then
        err "Unable to locate modules.yaml file. Ensure the genmodules.py output is in the /u01/opt/nvidia-driver directory."
    fi

    # refining packages to selected module; similar behavior if using 'dnf module install nvidia-driver:[stream]'
    module_array=($(yq "select(.data.stream == \"$module\") | .data.artifacts.rpms" modules.yaml | sed -E 's/^- //;s/.://'))

    # Check if the module array is empty.
    if [ ${module_array[@]} -eq 0 ]; then
    echo "No RPM packages found in '$topdir' for module: $module."
    exit 0
    fi

    # Loop through each package and create new 'repo' directory with specific RPMs for specified module
    mkdir "$topdir/repo_$module" -p
    for pkg in "${module_array[@]}"; do
        echo "Copying package for module $module: $pkg"
        cp "$topdir/repo/$pkg.rpm" $topdir/repo_$module || echo "Failed to copy $pkg, skipping..."
    done

    # Manual copy of the specific `kmod` for our kernel
    echo "Copying compiled 'kmod-nvidia' into repo_$module..."
    cp "$topdir/repo/kmod-nvidia-$version-$kernel-$release-$version-3$dist.$arch.rpm" "$topdir/repo_$module"
    
    eglx11=$(grep -E "egl-x11" primary.xml | grep "<location" | grep -E "${arch}" | awk -F '"' '{print $2}' | sort -rV | awk NR==1)
    eglwayland=$(grep -E "\<egl-wayland-[^a-zA-Z]" primary.xml | grep "<location" | grep -E "${arch}" | awk -F '"' '{print $2}' | sort -rV | awk 'NR==1')
    libnvidia=$(grep -E "libnvidia-" primary.xml | grep "<location" | grep -E "${arch}" | grep -E "${version}" | awk -F '"' '{print $2}')

    # Install additional packages not included within 'module'
    for rpm in $eglx11 $eglwayland; do
        echo "  -> $rpm"
        if [[ ! -f ${topdir}/repo_${module}/${rpm} ]]; then
            curl -sL "${baseURL}/${distro}/${arch}/${rpm}" --output "${topdir}/repo_${module}/${rpm}"
        fi
    done

    # Copy in libnividia files from original 'repo' directory
    for rpm in $libnvidia; do
        echo "  -> $rpm"
        if [[ ! -f ${topdir}/repo_${module}/${rpm} ]]; then
            cp "${topdir}/repo/${rpm}" "${topdir}/repo_${module}/${rpm}"
        fi
    done

    # downloads `binutils` depedency to enable usage of `kmod-nvidia` package
    sudo dnf download --downloaddir="${topdir}/repo_${module}" binutils

    #BUGFIX: Remove .i686 architecture files
    echo "removing '.i686' files from repo...${topdir}/repo_${module}"
    rm -f "${topdir}/repo_${module}/"*i686.rpm

    #BUGFIX: Remove nvidia-fabric-manager
    echo "removing 'nvidia-fabric-manager' file from repo...${topdir}/repo_${module}"
    rm -f "${topdir}/repo_${module}/"nvidia-fabric-manager-*.rpm

    #TO-DO: Add in clean-up for existing repo folder after build
    # Clean-up old module folder, rename module-specific directory
    # echo "Cleaning up legacy 'repo' directory; copying in 'repo_$module' directory"
    # cp -r "${topdir}/repo/repodata" "${topdir}/repo_${module}"
    # rm -rf repo
    # cp -r repo_$module repo
    # rm -rf repo_$module
}

#
# Stages
#

[[ $1 == "clean" ]] && clean_up

# Sanity check
if [[ -f $runfile ]] && [[ $version ]]; then
    echo ":: Building kmod package for $version @ $kernel-${release}${dist}"
else
    err "Missing runfile"
fi

# Create tarball from runfile contents
if [[ -f ${tarball}.tar.xz ]]; then
    echo "[SKIP] generate_tarballs()"
else
    echo "==> generate_tarballs()"
    generate_tarballs
fi

# Create X.509 certificate
if [[ -f $publicKey ]] && [[ -f $privateKey ]]; then
    echo "[SKIP] new_certificate()"
else
    echo "==> new_certificate()"
    new_certificate
fi

# Create GPG key
if [[ $gpgKey ]]; then
    echo "[SKIP] new_gpgkey()"
else
    echo "==> new_gpgkey()"
    new_gpgkey
fi

# Build RPMs
empty=$(find "$topdir/RPMS" -maxdepth 0 -type d -empty 2>/dev/null)
found=$(find "$topdir/RPMS" -mindepth 2 -maxdepth 2 -type f -name "*${version}*" 2>/dev/null)
if [[ ! -d "$topdir/RPMS" ]] || [[ $empty ]] || [[ ! $found ]]; then
    echo "==> kmod_rpm(${version})"
    kmod_rpm
else
    echo "[SKIP] kmod_rpm(${version})"
fi

# Sanity check
empty=$(find "$topdir/RPMS" -maxdepth 0 -type d -empty 2>/dev/null)
found=$(find "$topdir/RPMS" -mindepth 2 -maxdepth 2 -type f -name "*${version}*" 2>/dev/null)
if [[ $empty ]] || [[ ! $found ]]; then
    err "Missing kmod RPM package(s)"
elif [[ -z $gpgKey ]]; then
    err "Missing GPG key"
fi

# Sign RPMs
echo "==> sign_rpm($gpgKey)"
for pkg in "$topdir/RPMS/${arch}"/*; do
    sign_rpm "$pkg"
done
echo


if [[ -d "$OUTPUT" ]]; then
    mkdir -p "$downloads"
    # Copy RPMs built from https://github.com/NVIDIA/yum-packaging-*
    # nvidia-driver dkms-nvidia nvidia-kmod-common nvidia-modprobe nvidia-persistenced nvidia-plugin nvidia-settings nvidia-xconfig
    rsync -av "$topdir/RPMS/$arch"/*.rpm "$OUTPUT"/
    rsync -av "$OUTPUT"/*.rpm "$downloads"/
else
    echo "==> copy_rpms($baseURL/$distro/$arch)"
    # Copy RPMs from CUDA repository
    copy_rpms
    echo
fi

# Generate repodata
echo "==> make_repo()"
make_repo
echo

# .repo file
echo "==> repo_file()"
repo_file
echo

# refines repo for specific driver module
echo "==> select_module()"
select_module
echo