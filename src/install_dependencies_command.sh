install_age_plugin_yubikey() {
    printf "Downloading and extracting age-plugin-yubikey-v0.5.0-x86_64-linux.tar.gz..."
    tarfile_url="https://github.com/str4d/age-plugin-yubikey/releases/download/v0.5.0/age-plugin-yubikey-v0.5.0-x86_64-linux.tar.gz"
    sha256_checksum="03efa118cbd2842a971abb03958e45d67789afd3d69bf66b28483c89ce195d56"

    temp_dir=$(mktemp -d)
    tarfile="$temp_dir/age-plugin-yubikey.tar.gz"

    curl --silent -L -o "$tarfile" "$tarfile_url"
    tar -xzf "$tarfile" -C "$temp_dir"

    extracted_binary="$temp_dir/age-plugin-yubikey/age-plugin-yubikey"
    if [[ ! -f "$extracted_binary" ]]; then
        echo "[-] Failed to extract the age-plugin-yubikey binary."
        rm -rf "$temp_dir"
        exit 1
    fi
    printf " done.\n"

    actual_checksum=$(sha256sum "$extracted_binary" | awk '{ print $1 }')
    if [[ "$actual_checksum" != "$sha256_checksum" ]]; then
        echo "[-] Checksum mismatch. Downloaded file is invalid."
        rm -rf "$temp_dir"
        exit 1
    fi

    echo "age-plugin-yubikey SHA-256 checksum is valid."
    destination="$HOME/.local/bin/age-plugin-yubikey"

    if [ ! -d "$(basename $destination)" ]; then
        mkdir -p "$(basename $destination)"
    fi
    mv "$extracted_binary" "$destination"
    echo "Binary has been saved to: $destination"

    rm -rf "$temp_dir"
}

declare -A binary_to_package=(
    [age]="age"
    [openssl]="openssl"
    [psql]="postgresql"
    [ssh-keygen]="openssh"
    [ykman]="yubikey-manager"
    [yubico-piv-tool]="yubico-piv-tool"
)

packages_to_install=()

for binary in "${!binary_to_package[@]}"; do
    printf "Checking for $binary..."
    if ! command -v "$binary" &> /dev/null; then
        echo " done. $binary is missing, ${binary_to_package[$binary]} will be installed with DNF."
        packages_to_install+=("${binary_to_package[$binary]}")
    else
        echo " done. $binary found at: $(command -v $binary)"
    fi
done

if [ ${#packages_to_install[@]} -ne 0 ]; then
    echo "Installing missing packages: ${packages_to_install[@]}"
    sudo dnf install -y "${packages_to_install[@]}" > /dev/null
fi

binary="age-plugin-yubikey"
printf "Checking for $binary..."
if ! command -v "$binary" &> /dev/null; then
    echo " done. $binary is missing, $binary will be installed from GitHub."
    install_age_plugin_yubikey
else
    echo " done. $binary found at: $(command -v $binary)"
fi
