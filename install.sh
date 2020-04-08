#!/bin/bash

set -e
set -x

if [ -e /dev/vda ]; then
  device=/dev/vda
elif [ -e /dev/sda ]; then
  device=/dev/sda
else
  echo "ERROR: There is no disk available for installation" >&2
  exit 1
fi
export device


####
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk ${device}
  o # create a DOS partition table
  n # new partition
  p # primary partition
  1 # partition number 1
    # default - start at beginning of disk 
  +200M # 100 MB boot parttion
  n # new partition
  p # primary partition
  2 # partition number 2
    # default - start next to the partiton1
    # default - until the end of the disk
  t # change partition type
  2 # select partition 2
  8e # type Linux LVM
  w # write the partition table
  q # and we're done
EOF

boot_partition=${device}1
lvm_partition=${device}2

pvcreate ${lvm_partition}
pv_path=${lvm_partition}

vg_name=sys

vgcreate ${vg_name} ${pv_path}
vg_path=/dev/${vg_name}

lv_swap_name=swap
lv_log_name=log
lv_root_name=root

lvcreate -L 2G ${vg_name} -n ${lv_swap_name}
lvcreate -l 100%FREE ${vg_name} -n ${lv_root_name}

lv_swap_path=${vg_path}/swap
lv_root_path=${vg_path}/root

mkswap ${lv_swap_path}

mkfs.ext4 ${lv_root_path}
mkfs.ext4 ${boot_partition}

mount ${lv_root_path} /mnt
mkdir /mnt/boot
mount ${boot_partition} /mnt/boot


if [ -n "${MIRROR}" ]; then
  echo "Server = ${MIRROR}" >/etc/pacman.d/mirrorlist
else
  pacman -Sy reflector --noconfirm
  reflector --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
fi

pacstrap -M /mnt base base-devel linux-firmware linux grub lvm2
swapon ${lv_swap_path}
genfstab -p /mnt >>/mnt/etc/fstab
swapoff ${lv_swap_path}


arch-chroot /mnt <<EOF
ln -sf /usr/share/zoneinfo/Europe/Stockholm /etc/localtime
echo "archvm " > /etc/hostname 
reflector --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
sed -i 's/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/HOOKS=(base udev autodetect modconf block lvm2 filesystems keyboard fsck)/' /etc/mkinitcpio.conf
mkinitcpio -p linux
grub-install --target=i386-pc ${target_device}
sed -i 's/GRUB_PRELOAD_MODULES="part_gpt part_msdos"/GRUB_PRELOAD_MODULES="part_gpt part_msdos lvm2"/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
exit
EOF
