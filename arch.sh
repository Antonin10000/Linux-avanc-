#!/bin/bash

### Vérification des droits root ###
if [[ $EUID -ne 0 ]]; then
    echo "Ce script doit être exécuté en tant que root."
    exit 1
fi

### Variables ###
DISK="/dev/sda"
HOSTNAME="arch-linux"
USERNAME="user"
USERPASS="azerty123"
ROOTPASS="azerty123"
SHARE_NAME="shared"
VIRTUALBOX_DIR="vbox_storage"
CRYPT_PART="cryptvolume"

### 🛠️ Préparation du disque ###
echo "[1/6] Partitionnement du disque..."
parted -s $DISK mklabel gpt
parted -s $DISK mkpart ESP fat32 1MiB 512MiB
parted -s $DISK set 1 esp on
parted -s $DISK mkpart primary 512MiB 100%

### 🔒 Chiffrement du disque ###
echo "[2/6] Chiffrement avec LUKS..."
echo -n "$ROOTPASS" | cryptsetup luksFormat ${DISK}2
echo -n "$ROOTPASS" | cryptsetup open ${DISK}2 cryptlvm

### 📦 Création de LVM ###
pvcreate /dev/mapper/cryptlvm
vgcreate vg0 /dev/mapper/cryptlvm
lvcreate -L 10G -n $CRYPT_PART vg0   # Volume chiffré monté à la main
lvcreate -L 10G -n root vg0          # Système principal
lvcreate -L 5G -n home vg0           # Dossier personnel
lvcreate -L 2G -n swap vg0           # Swap
lvcreate -L 5G -n $SHARE_NAME vg0    # Dossier partagé
lvcreate -L 10G -n $VIRTUALBOX_DIR vg0  # Stockage VirtualBox
lvcreate -l 100%FREE -n var vg0      # Reste de l’espace pour /var

### 📂 Formatage ###
mkfs.fat -F32 ${DISK}1
mkfs.ext4 /dev/vg0/root
mkfs.ext4 /dev/vg0/home
mkfs.ext4 /dev/vg0/$SHARE_NAME
mkfs.ext4 /dev/vg0/$VIRTUALBOX_DIR
mkfs.ext4 /dev/vg0/var
mkswap /dev/vg0/swap

### 🔄 Montage ###
mount /dev/vg0/root /mnt
mkdir -p /mnt/{boot,home,swap,var}
mount /dev/vg0/home /mnt/home
mount /dev/vg0/var /mnt/var
mount ${DISK}1 /mnt/boot
swapon /dev/vg0/swap

### 📦 Installation de base ###
echo "[3/6] Installation de base..."
pacstrap /mnt base linux linux-firmware vim sudo networkmanager grub efibootmgr lvm2

### 🔗 Configuration système ###
echo "[4/6] Configuration système..."
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt <<EOF
echo "$HOSTNAME" > /etc/hostname
echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc
echo "KEYMAP=fr" > /etc/vconsole.conf
locale-gen
echo "root:$ROOTPASS" | chpasswd

# GRUB avec chiffrement
echo "GRUB_CMDLINE_LINUX=\"cryptdevice=/dev/sda2:cryptlvm root=/dev/mapper/vg0-root\"" >> /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Activation services
systemctl enable NetworkManager
EOF

### 👤 Création de l’utilisateur ###
echo "[5/6] Création de l'utilisateur..."
arch-chroot /mnt useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$USERPASS" | arch-chroot /mnt chpasswd
echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers

### 🖥️ Installation Hyprland ###
echo "[6/6] Installation de Hyprland..."
arch-chroot /mnt pacman -S --noconfirm hyprland alacritty rofi thunar firefox git base-devel

### 🚀 Post-installation ###
echo "Installation terminée !"
echo "Après le redémarrage, pensez à monter manuellement le volume chiffré : /dev/vg0/$CRYPT_PART"
umount -R /mnt
swapoff -a
reboot
