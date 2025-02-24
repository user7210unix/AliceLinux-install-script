#!/bin/bash

# Define variables
ROOTFS_URL="https://codeberg.org/emmett1/alicelinux/releases/download/20241006/alicelinux-rootfs-20241006.tar.xz"
SHA256SUM_URL="${ROOTFS_URL}.sha256sum"
MOUNT_POINT="/mnt/alice"
REPO_DIR="/var/lib/alicelinux"
APKG_CONF="/etc/apkg.conf"
PACKAGES=(
    "autils"
    "b3sum"
    "baselayout"
    "binutils"
    "bison"
    "busybox"
    "bzip2"
    "ca-certificates"
    "curl"
    "file"
    "flex"
    "gcc"
    "git"
    "gmp"
    "initscripts"
    "linux-headers"
    "m4"
    "make"
    "mpc"
    "mpfr"
    "musl"
    "openssl"
    "patch"
    "spm"
    "xz"
    "zlib"
    "linux"
    "linux-firmware"
    "linux-firmware-nvidia"
    "grub"
    "meson"
    "cmake"
    "pkgconf"
    "libtool"
    "automake"
    "perl"
    "wpa_supplicant"
    "dhcpcd"
    "tzdata"
)

# Prompt for user input
echo "Please enter the following details:"
read -p "Username: " USERNAME
read -p "SSID: " SSID
read -sp "SSID Password: " SSID_PASSWORD
echo
read -p "Timezone (e.g., Asia/Kuala_Lumpur): " TIMEZONE

# Update package database and install necessary tools on the host system
echo "Updating package database and installing necessary tools on the host system..."
sudo pacman -Syu --needed arch-install-scripts curl tar git ${PACKAGES[@]}

# Download the rootfs tarball and its sha256sum file
echo "Downloading AliceLinux rootfs tarball and sha256sum file..."
curl -O $ROOTFS_URL
curl -O $SHA256SUM_URL

# Verify the checksum
echo "Verifying checksum..."
sha256sum -c alicelinux-rootfs-20241006.tar.xz.sha256sum
if [ $? -ne 0 ]; then
    echo "Checksum verification failed!"
    exit 1
fi

# Prepare the partition and filesystem
echo "Preparing the partition and filesystem..."
sudo mkfs.ext4 /dev/sda1  # Root partition
sudo mkswap /dev/sda2     # Swap partition (optional)
sudo swapon /dev/sda2     # Enable swap
sudo mkdir -p $MOUNT_POINT
sudo mount /dev/sda1 $MOUNT_POINT

# Extract the rootfs tarball
echo "Extracting the rootfs tarball..."
sudo tar xvf alicelinux-rootfs-20241006.tar.xz -C $MOUNT_POINT

# Enter chroot
echo "Entering chroot environment..."
sudo $MOUNT_POINT/usr/bin/apkg-chroot $MOUNT_POINT /bin/bash <<EOF

# Clone Alice repos
echo "Cloning Alice repositories..."
cd $REPO_DIR
git clone --depth=1 https://codeberg.org/emmett1/alicelinux

# Configure apkg
echo "Configuring apkg..."
echo 'export CFLAGS="-O3 -march=x86-64 -pipe"' >> $APKG_CONF
echo 'export CXXFLAGS="$CFLAGS"' >> $APKG_CONF
echo 'export MAKEFLAGS="-j6"' >> $APKG_CONF
echo 'export NINJAJOBS="6"' >> $APKG_CONF
echo 'APKG_REPO="/var/lib/alicelinux/repos/core /var/lib/alicelinux/repos/extra"' >> $APKG_CONF

# Create necessary directories
mkdir -p /var/cache/pkg
mkdir -p /var/cache/src
mkdir -p /var/cache/work

# Add directories to apkg.conf
echo 'APKG_PACKAGE_DIR=/var/cache/pkg' >> $APKG_CONF
echo 'APKG_SOURCE_DIR=/var/cache/src' >> $APKG_CONF
echo 'APKG_WORK_DIR=/var/cache/work' >> $APKG_CONF

# Perform a full system upgrade
echo "Performing full system upgrade..."
apkg -U

# Install development packages
echo "Installing development packages..."
apkg -I meson cmake pkgconf libtool automake perl

# Install specified packages
echo "Installing specified packages..."
for package in "${PACKAGES[@]}"; do
    apkg -I ${package%-*}
done

# Install kernel and firmware
echo "Installing kernel and firmware..."
apkg -I linux linux-firmware linux-firmware-nvidia

# Install bootloader
echo "Installing bootloader..."
apkg -I grub
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

# Set hostname
echo "Setting hostname..."
echo "alice" > /etc/hostname

# Configure fstab
echo "Configuring fstab..."
echo '/dev/sda1 / ext4 defaults 0 1' >> /etc/fstab
echo '/dev/sda2 swap swap defaults 0 0' >> /etc/fstab

# Enable runit services
echo "Enabling runit services..."
ln -s /etc/sv/tty1 /var/service
ln -s /etc/sv/tty2 /var/service
ln -s /etc/sv/tty3 /var/service

# Setup user and password
echo "Setting up user and password..."
adduser $USERNAME
adduser $USERNAME wheel
adduser $USERNAME input
adduser $USERNAME video
adduser $USERNAME audio
passwd

# Setup networking
echo "Setting up networking..."
apkg -I wpa_supplicant dhcpcd
wpa_passphrase $SSID $SSID_PASSWORD >> /etc/wpa_supplicant.conf
ln -s /etc/sv/wpa_supplicant /var/service
ln -s /etc/sv/dhcpcd /var/service

# Set timezone
echo "Setting timezone..."
apkg -I tzdata
ln -s /usr/share/zoneinfo/$TIMEZONE /etc/localtime

EOF

# Exit chroot and unmount
echo "Exiting chroot and unmounting..."
sudo swapoff /dev/sda2
sudo umount $MOUNT_POINT

echo "Installation complete! Reboot your system."
