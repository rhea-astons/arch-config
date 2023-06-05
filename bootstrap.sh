#!/bin/bash

set -e

source packages

die() { echo "$*" >&2; exit 2; }

needs_arg() { if [ -z "$OPTARG" ]; then die "Missing argument for --$OPT option"; fi }

usage() {
  echo "Usage: boostrap.sh [OPTIONS] --disk=<DISK_PATH> --hostname=<HOSTNAME>"
  echo ""
  echo "Options:"
  echo "  --help               Show usage"
  echo "  --encrypt-root       Encrypt root disk"
}

disk=""
encrypt=""
hostname=""

if [ $# -eq 0 ]; then
  echo "ERROR: Missing mandatory arguments!"
  echo ""
  usage
  exit 1
fi

while getopts h-: OPT; do
  # support long options: https://stackoverflow.com/a/28466267/519360
  if [ "$OPT" = "-" ]; then  # long option: reformulate OPT and OPTARG
    OPT="${OPTARG%%=*}"      # extract long option name
    OPTARG="${OPTARG#$OPT}"  # extract long option argument (may be empty)
    OPTARG="${OPTARG#=}"     # if long option argument, remove assigning `=`
  fi

  case $OPT in
    disk)
      needs_arg
      disk="$OPTARG"
      ;;
    hostname)
      needs_arg
      hostname="$OPTARG"
      ;;
    encrypt-root)
      encrypt=true
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done
shift $((OPTIND -1)) # remove parsed options and args from $@ list

if [ -z $disk ] || [ -z $hostname ]; then
  echo "ERROR: Missing mandatory arguments!"
  echo ""
  usage
  exit 1
fi

echo "* Enabling NTP"
timedatectl set-ntp true

echo "* Updating mirrors list with reflector"
reflector -c ch,de,fr --age 24 --sort rate --save /etc/pacman.d/mirrorlist > /dev/null 2>&1

echo "* Partitioning the disk"
sgdisk -og $disk > /dev/null
sgdisk -n 1:0:+550M -c 1:"EFI" -t 1:ef00 $disk > /dev/null
sgdisk -n 2:0:"$ENDSECTOR" -c 2:$hostname $disk > /dev/null

partprobe $disk
sleep 2

echo "* Formating partitions"
mkfs.vfat -F 32 -n EFI /dev/disk/by-partlabel/EFI > /dev/null

root_part=/dev/disk/by-partlabel/$hostname

if [ -n "$encrypt" ]; then
  cryptsetup \
    --cipher=aes-xts-plain64 \
    --key-size=512 \
    --hash=sha512 \
    --iter-time=3000 \
    --pbkdf=pbkdf2 \
    --use-random \
    luksFormat /dev/disk/by-partlabel/$hostname
  cryptsetup luksOpen /dev/disk/by-partlabel/$hostname $hostname
  root_part=/dev/mapper/$hostname
fi

mkfs.btrfs -fL $hostname $root_part > /dev/null
mkfs.vfat -F32 -n EFI /dev/disk/by-partlabel/EFI > /dev/null

echo "* Mounting partitions"
mount $root_part /mnt
btrfs su cr /mnt/@ > /dev/null
btrfs su cr /mnt/@home > /dev/null
btrfs su cr /mnt/@snapshots > /dev/null
btrfs su cr /mnt/@logs > /dev/null
btrfs su cr /mnt/@pkg > /dev/null
btrfs su cr /mnt/@tmp > /dev/null

chattr +c /mnt/@logs
chattr +c /mnt/@tmp

umount /mnt

mount -o defaults,noatime,nodiratime,compress=zstd,space_cache=v2,ssd,discard,subvol=@ $root_part /mnt
mkdir -p /mnt/{home,.snapshots,var/log/,var/cache/pacman/pkg,tmp,boot}
mount -o defaults,noatime,nodiratime,compress=zstd,space_cache=v2,ssd,discard,subvol=@home $root_part /mnt/home
mount -o defaults,noatime,nodiratime,compress=zstd,space_cache=v2,ssd,discard,subvol=@snapshots $root_part /mnt/.snapshots
mount -o defaults,noatime,nodiratime,compress=zstd,space_cache=v2,ssd,discard,subvol=@logs $root_part /mnt/var/log
mount -o defaults,noatime,nodiratime,compress=zstd,space_cache=v2,ssd,discard,subvol=@pkg $root_part /mnt/var/cache/pacman/pkg
mount -o defaults,noatime,nodiratime,compress=zstd,space_cache=v2,ssd,discard,subvol=@tmp $root_part /mnt/tmp
mount /dev/disk/by-partlabel/EFI /mnt/boot

echo "* Installing base system"
pacstrap /mnt ${base_packages[@]} > /dev/null

echo "* Generating new fstab"
genfstab /mnt >> /mnt/etc/fstab

echo "* Setting hostname"
echo "$hostname" > /mnt/etc/hostname

echo "* Copying this repo to the new system (/opt/arch-config)"
cp -r ../arch-config /mnt/opt
echo "DONE! Complete installation after chrooting to the new system"

