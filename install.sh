#!/bin/bash

# Get info from user for install
echo "What disk do you want to install Arch to? (e.g., sda)"
read -r selDisk

echo "Create a hostname:"
read -r HOSTNAME

echo "Are you on a laptop? (y/n)"
read -r laptop

echo "Create a user:"
read -r USERNAME
echo "Add a password:"
read -r PASSWORD

echo "Default root password is 'root'. Press Enter to continue."
echo "For installation purposes a temporary user is created. The credentials are temp and temp"
read -r

# Variables - adjust as needed
DISK="/dev/$selDisk"

# Update system clock
timedatectl set-ntp true

# Partition the disk (modify as needed)
echo "Partitioning the disk..."
(
  echo g      # Create a new empty GPT partition table
  echo n      # Create new EFI partition
  echo        # Default partition number (1)
  echo        # Default - start at beginning of disk
  echo +512M  # Size for EFI partition
  echo t      # Set type for partition
  echo 1      # Type 1 (EFI System)
  echo n      # Add another partition (root)
  echo        # Default partition number (2)
  echo        # Default - start immediately after preceding partition
  echo        # Default - extend to end of disk
  echo w      # Write changes
) | fdisk "$DISK"

# Format partitions
echo "Formatting partitions..."
if mkfs.fat -F32 "${DISK}1"; then
  echo "EFI partition formatted successfully."
else
  echo "Failed to format EFI partition. Please check the disk."
  exit 1
fi

if mkfs.ext4 "${DISK}2"; then
  echo "Root partition formatted successfully."
else
  echo "Failed to format root partition. Please check the disk."
  exit 1
fi

# Mount the file systems
echo "Mounting partitions..."
mount "${DISK}2" /mnt
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

# Install base packages
echo "Installing base packages..."
pacstrap /mnt base linux linux-firmware

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the system
echo "Entering chroot environment..."
arch-chroot /mnt /bin/bash <<EOF

# Set time zone
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
hwclock --systohc

# Localization
echo "en_GB.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_GB.UTF-8" > /etc/locale.conf

# Network configuration
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

# Set root password
echo "root:root" | chpasswd

# Install essential packages
pacman -S grub efibootmgr networkmanager nano openssh sudo dotnet-sdk iwd bash-completion --noconfirm
pacman -S --needed base-devel git wget curl --noconfirm

# Install yay AUR helper
useradd "temp"
echo "temp:temp" | chpasswd

git clone https://aur.archlinux.org/yay.git /tmp/yay
cd /tmp/yay || { echo "Failed to change directory to yay"; exit 1; }
su - temp -c "makepkg -si --noconfirm"

# Install GRUB bootloader
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Config iwd
mkdir -p /etc/iwd
echo "[General]\nEnableNetworkConfiguration=true" >> /etc/iwd/main.conf

# Enable services
systemctl enable NetworkManager
systemctl enable iwd
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable sshd

# Create a new user
useradd -m -G wheel "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd

# Allow wheel group to use sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Add custom commands & edit .bashrc
cp /bin/pacman /bin/pac
if [ "$laptop" = "y" ]; then
  pacman -S acpi --noconfirm
  echo "export PS1='[\$(acpi -b | grep -P -o '[0-9]+(?=%)')%]\u@\h: \w\$'" >> "/home/$USERNAME/.bashrc"
else
  echo "export PS1='\u@\h: \w\$'" >> "/home/$USERNAME/.bashrc"
fi

echo "KEYMAP=uk" >> /etc/vconsole.conf

printf '\nif [ -f /usr/share/bash-completion/bash_completion ]; then\n    . /usr/share/bash-completion/bash_completion\nfi\n' >> "/home/$USERNAME/.bashrc"

complete -cf sudo
userdel temp

EOF

# Unmount and reboot
echo "Unmounting and rebooting..."
umount -R /mnt
reboot
