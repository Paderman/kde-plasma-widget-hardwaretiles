# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Sourced by hw-discover.sh and install-sensors.sh: which package manager to use
# for lm-sensors on this distribution. Sets
#   PM        apt | dnf | zypper | pacman | immutable | ""   ("" = unknown)
#   PKG       package name of lm-sensors for PM
#   DISTRO    pretty name of the distribution
# only real package managers in system paths (e.g. /usr/games/pacman is a game)
_has_pm() { [ -x "/usr/bin/$1" ] || [ -x "/bin/$1" ]; }

detect_distro() {
    PM=""; PKG=""; DISTRO=""
    ids=""
    osr=${SENSORDECK_OSRELEASE:-/etc/os-release}   # override only for tests
    if [ -r "$osr" ]; then
        DISTRO=$(. "$osr" && echo "${PRETTY_NAME:-$NAME}")
        ids=$(. "$osr" && echo "$ID $ID_LIKE")
    fi
    # image-based systems (Fedora Kinoite, Bazzite, SteamOS, openSUSE Aeon/Kalpa …):
    # packages are not installed with the normal package manager
    if [ -e /run/ostree-booted ] || command -v steamos-readonly >/dev/null 2>&1 \
       || command -v transactional-update >/dev/null 2>&1; then
        PM=immutable
        return
    fi
    for id in $ids; do
        case $id in
            debian|ubuntu|neon|linuxmint|pop|kubuntu|elementary|zorin)
                _has_pm apt-get && { PM=apt; PKG=lm-sensors; return; } ;;
            fedora|rhel|centos|rocky|almalinux|nobara|ultramarine)
                _has_pm dnf && { PM=dnf; PKG=lm_sensors; return; } ;;
            opensuse*|suse|sles)
                _has_pm zypper && { PM=zypper; PKG=sensors; return; } ;;
            arch|manjaro|endeavouros|cachyos|garuda|artix)
                _has_pm pacman && { PM=pacman; PKG=lm_sensors; return; } ;;
        esac
    done
    # unknown name: go by the package manager that exists
    if _has_pm apt-get; then PM=apt; PKG=lm-sensors
    elif _has_pm dnf; then PM=dnf; PKG=lm_sensors
    elif _has_pm zypper; then PM=zypper; PKG=sensors
    elif _has_pm pacman; then PM=pacman; PKG=lm_sensors
    fi
}
