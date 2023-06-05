# Arch Linux configuration files

## Bootstrap
```
loadkeys ch_FR-latin1
pacman -Sy git
git clone https://github.com/rhea-astons/arch-config.git
cd arch-config
./bootstrap.sh --disk=/dev/sda --hostname=arch
```
In case of errors while importing keys:
```
pacman -Sy archlinux-keyring
```

