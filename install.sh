#!/bin/bash

set -e

die() { echo "$*" >&2; exit 2; }

needs_arg() { if [ -z "$OPTARG" ]; then die "Missing argument for --$OPT option"; fi }

usage() {
  echo "Usage: install.sh [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --help               Show usage"
  echo "  --swap=SIZE_IN_GB    Swap size, default=16"
  echo "  --timezone=TIMEZONE  Timezone (as in /usr/share/zoneinfo/), default: Europe/Zurich"
}

swap=16
timezone="Europe/Zurich"

#if [ $# -eq 0 ]; then
#  echo "ERROR: Missing mandatory arguments!"
#  echo ""
#  usage
#  exit 1
#fi

while getopts h-: OPT; do
  # support long options: https://stackoverflow.com/a/28466267/519360
  if [ "$OPT" = "-" ]; then  # long option: reformulate OPT and OPTARG
    OPT="${OPTARG%%=*}"      # extract long option name
    OPTARG="${OPTARG#$OPT}"  # extract long option argument (may be empty)
    OPTARG="${OPTARG#=}"     # if long option argument, remove assigning `=`
  fi

  case $OPT in
    timezone)
      needs_arg
      timezone="$OPTARG"
      ;;
    #hostname)
    #  needs_arg
    #  hostname="$OPTARG"
    #  ;;
    swap)
      needs_arg
      swap="$OPTARG"
      ;;
    #encrypt-root)
    #  encrypt=true
    #  ;;
    *)
      usage
      exit 1
      ;;
  esac
done
shift $((OPTIND -1)) # remove parsed options and args from $@ list

#if [ -z $disk ] || [ -z $hostname ]; then
#  echo "ERROR: Missing mandatory arguments!"
#  echo ""
#  usage
#  exit 1
#fi

hostname=$(cat /etc/hostname)

echo "* Setting time zone and syncing hardware clock"
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc --utc

echo "* Setting console keymap and font"
echo "KEYMAP=fr_CH-latin1" > /etc/vconsole.conf

echo "* Generating locales"
sed -i '/en_US.UTF-8/s/^#//g' /etc/locale.gen
sed -i '/fr_CH.UTF-8/s/^#//g' /etc/locale.gen
locale-gen > /dev/null

echo "* Generating locale configuration"
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "LC_COLLATE=fr_CH.UTF-8" >> /etc/locale.conf
echo "LC_MEASUREMENT=fr_CH.UTF-8" >> /etc/locale.conf
echo "LC_MONETARY=fr_CH.UTF-8" >> /etc/locale.conf
echo "LC_NUMERIC=fr_CH.UTF-8" >> /etc/locale.conf
echo "LC_TIME=fr_CH.UTF-8" >> /etc/locale.conf

echo "* Updating hosts file"
echo "127.0.0.1 $hostname.localdomain $hostname" >> /etc/hosts
echo "::1 localhost.localdomain localhost" >> /etc/hosts

echo "* Creating swap file"
btrfs su cr /swap > /dev/null
chattr +C /swap
touch /swap/swapfile
swap=$((1024 * swap))
dd if=/dev/zero of=/swap/swapfile bs=1024K count=$swap > /dev/null
chmod 600 /swap/swapfile
mkswap /swap/swapfile > /dev/null
swapon /swap/swapfile > /dev/null
echo "/swap/swapfile none swap sw 0 0" >> /etc/fstab

