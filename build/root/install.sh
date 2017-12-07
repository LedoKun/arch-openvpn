#!/bin/bash

# exit script if return code != 0
set -e

# pacman packages
####

# define pacman packages
pacman_packages="kmod openvpn privoxy dnsutils"

# install pre-reqs
pacman -S --needed $pacman_packages --noconfirm

# cleanup
yes|pacman -Scc
rm -rf /usr/share/locale/*
rm -rf /usr/share/man/*
rm -rf /usr/share/gtk-doc/*
rm -rf /tmp/*
