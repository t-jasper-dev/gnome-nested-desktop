#!/usr/bin/env bash
# Installiert die Systempakete, die gnome-nested-desktop auf einer normalen
# Distribution braucht. Es wird nichts gebündelt: GNOME, gsd, Portal und die
# X11-Werkzeuge kommen aus dem System.
#
# Aufruf: ./install-deps.sh [--dry-run]
#
# Hinweis SteamOS: Das Root-Dateisystem ist schreibgeschützt. Pakete dort sind
# nicht update-fest. SteamOS wird deshalb nicht automatisch verändert.

set -euo pipefail

DRY_RUN=0
case "${1:-}" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
        echo "Aufruf: ./install-deps.sh [--dry-run]"
        exit 0
        ;;
    "") ;;
    *) echo "Unbekannte Option: $1" >&2; exit 1 ;;
esac

say()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'FEHLER: %s\n' "$*" >&2; exit 1; }

run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '  %s' "$@"
        printf '\n'
    else
        "$@"
    fi
}

[ "$(id -u)" -eq 0 ] && SUDO="" || SUDO="sudo"

# shellcheck disable=SC1091
. /etc/os-release
DISTRO="${ID:-unknown} ${ID_LIKE:-}"

say "Prüfe vorhandene GNOME-Bestandteile"

missing=()
for c in gnome-shell gnome-control-center nautilus xdotool xprop xrandr dconf gdbus dbus-run-session; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
gsd_found=0
for p in /usr/libexec/gsd-rfkill /usr/lib/gsd-rfkill; do
    [ -x "$p" ] && gsd_found=1
done
[ "$gsd_found" = 1 ] || missing+=("gsd-rfkill")

xsettings_found=0
for p in /usr/libexec/gsd-xsettings /usr/lib/gsd-xsettings; do
    [ -x "$p" ] && xsettings_found=1
done
[ "$xsettings_found" = 1 ] || missing+=("gsd-xsettings")

portal_found=0
for p in /usr/libexec/xdg-desktop-portal-gnome /usr/lib/xdg-desktop-portal-gnome; do
    [ -x "$p" ] && portal_found=1
done
[ "$portal_found" = 1 ] || missing+=("xdg-desktop-portal-gnome")

DEVKIT_SYSTEM=0
for p in /usr/libexec/mutter-devkit /usr/lib/mutter-devkit /usr/lib64/mutter-devkit; do
    [ -x "$p" ] && DEVKIT_SYSTEM=1
done
DEVKIT_LOCAL=0
[ -x "${XDG_DATA_HOME:-$HOME/.local/share}/mutter-devkit/mutter-devkit" ] && DEVKIT_LOCAL=1

if [ ${#missing[@]} -eq 0 ] && { [ "$DEVKIT_SYSTEM" = 1 ] || [ "$DEVKIT_LOCAL" = 1 ]; }; then
    say "Alles vorhanden"
    echo "mutter-devkit: $([ "$DEVKIT_SYSTEM" = 1 ] && echo System || echo lokal)"
    exit 0
fi

if [ ${#missing[@]} -gt 0 ]; then
    printf 'Fehlend: %s\n' "${missing[*]}"
fi

say "Distribution: $DISTRO"

case "$DISTRO" in
    *steamos*)
        warn "SteamOS hat ein schreibgeschütztes Root-Dateisystem."
        warn "Ein natives GNOME würde bei Systemupdates verloren gehen."
        warn "Für SteamOS ist ein Container/Rootfs der dauerhafte Weg."
        warn "Der Installer ändert SteamOS nicht automatisch."
        exit 1
        ;;
    *bazzite*|*fedora*|*rhel*|*centos*)
        PKGS=(
            gnome-shell mutter gnome-settings-daemon
            xdg-desktop-portal xdg-desktop-portal-gnome
            gnome-control-center nautilus
            dconf gsettings-desktop-schemas glib2
            dbus-daemon dbus-tools
            xdotool xprop xrandr xwininfo
            procps-ng iproute
        )
        if command -v rpm-ostree >/dev/null 2>&1; then
            warn "rpm-ostree-System: Pakete werden als Layer installiert und"
            warn "werden erst nach einem Neustart aktiv."
            run "$SUDO" rpm-ostree install "${PKGS[@]}"
            warn "Danach neu starten."
        else
            run "$SUDO" dnf install -y "${PKGS[@]}"
        fi
        ;;
    *cachyos*|*arch*|*manjaro*|*endeavouros*)
        PKGS=(
            gnome-shell mutter mutter-devkit gnome-settings-daemon
            xdg-desktop-portal xdg-desktop-portal-gnome
            gnome-control-center nautilus
            dconf gsettings-desktop-schemas glib2
            dbus
            xdotool xorg-xprop xorg-xrandr xorg-xwininfo
            procps-ng iproute2
        )
        run "$SUDO" pacman -S --needed --noconfirm "${PKGS[@]}"
        ;;
    *debian*|*ubuntu*|*linuxmint*|*pop*)
        PKGS=(
            gnome-shell mutter gnome-settings-daemon
            xdg-desktop-portal xdg-desktop-portal-gnome
            gnome-control-center nautilus
            dconf-cli gsettings-desktop-schemas libglib2.0-bin
            dbus
            xdotool x11-utils x11-xserver-utils
            procps iproute2
        )
        run "$SUDO" apt update
        run "$SUDO" apt install -y "${PKGS[@]}"
        ;;
    *opensuse*|*suse*)
        PKGS=(
            gnome-shell mutter gnome-settings-daemon
            xdg-desktop-portal xdg-desktop-portal-gnome
            gnome-control-center nautilus
            dconf gsettings-desktop-schemas glib2-tools
            dbus-1
            xdotool xprop xrandr xwininfo
            procps iproute2
        )
        run "$SUDO" zypper --non-interactive install "${PKGS[@]}"
        ;;
    *)
        die "Unbekannte Distribution '$DISTRO'. Installiere manuell: gnome-shell, mutter, mutter-devkit, gnome-settings-daemon, xdg-desktop-portal-gnome, gnome-control-center, nautilus, xdotool, xprop, xrandr."
        ;;
esac

if [ "$DRY_RUN" = 0 ]; then
    say "Prüfe Devkit"
    devkit_found=0
    for p in /usr/libexec/mutter-devkit /usr/lib/mutter-devkit /usr/lib64/mutter-devkit; do
        [ -x "$p" ] && devkit_found=1
    done
    if [ "$devkit_found" = 1 ]; then
        echo "System-mutter-devkit vorhanden"
    elif [ -x "${XDG_DATA_HOME:-$HOME/.local/share}/mutter-devkit/mutter-devkit" ]; then
        echo "Lokales mutter-devkit vorhanden"
    else
        warn "Kein mutter-devkit gefunden."
        warn "Auf Fedora: sudo dnf install mutter-devkit"
        warn "Auf Arch: sudo pacman -S mutter-devkit"
        warn "Auf Debian/Ubuntu ist mutter-devkit oft nicht paketiert; dann bauen."
    fi
fi

say "Fertig"
echo "Danach: ./install.sh"
