#!/usr/bin/env bash
# gnome-nested-desktop – Bootstrap-Installer
#
# Laedt das Projektarchiv von GitHub herunter und ruft install.sh auf.
# Damit reicht eine Zeile:
#
#   curl -fsSL https://raw.githubusercontent.com/t-jasper-dev/gnome-nested-desktop/main/get.sh | bash
#   wget -qO- https://raw.githubusercontent.com/t-jasper-dev/gnome-nested-desktop/main/get.sh | bash
#
# Optionen werden an install.sh weitergegeben, z. B.:
#
#   ... | bash -s -- --skip-steam
#
# Umgebungsvariablen:
#   GND_REPO   Repository (Standard: t-jasper-dev/gnome-nested-desktop)
#   GND_REF    Branch oder Tag (Standard: main)
#
# Es wird nichts installiert, was install.sh nicht auch selbst installiert.
# install.sh legt auch den Steam-Shortcut an, richtet den Gaming-Mode-Starter
# für Steam ein und beendet Steam für das Schreiben nach Rückfrage (Enter = ja).

set -euo pipefail

REPO="${GND_REPO:-t-jasper-dev/gnome-nested-desktop}"
REF="${GND_REF:-main}"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mFEHLER:\033[0m %s\n' "$*" >&2; exit 1; }

# Wird get.sh aus einem lokalen Checkout gestartet, direkt installieren.
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || true)"
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/install.sh" ] && [ -d "$SELF_DIR/assets" ]; then
    say "Lokaler Checkout: $SELF_DIR"
    exec bash "$SELF_DIR/install.sh" "$@"
fi

command -v tar >/dev/null 2>&1 || die "tar fehlt"

DOWNLOADER=""
if command -v curl >/dev/null 2>&1; then
    DOWNLOADER="curl"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOADER="wget"
else
    die "Weder curl noch wget gefunden"
fi

fetch() {
    # fetch URL ZIEL
    if [ "$DOWNLOADER" = "curl" ]; then
        curl -fsSL --retry 2 --max-time 300 "$1" -o "$2"
    else
        wget -q --tries=3 --timeout=300 -O "$2" "$1"
    fi
}

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gnome-nested-desktop.XXXXXX")"
cleanup() { rm -rf -- "$TMP_DIR"; }
trap cleanup EXIT

ARCHIVE="$TMP_DIR/project.tar.gz"
URLS=(
    "https://codeload.github.com/$REPO/tar.gz/refs/heads/$REF"
    "https://github.com/$REPO/archive/refs/heads/$REF.tar.gz"
)
if printf '%s' "$REF" | grep -Eq '^v?[0-9]'; then
    URLS=(
        "https://codeload.github.com/$REPO/tar.gz/refs/tags/$REF"
        "https://github.com/$REPO/archive/refs/tags/$REF.tar.gz"
        "https://codeload.github.com/$REPO/tar.gz/refs/heads/$REF"
    )
fi

say "Lade $REPO ($REF)"
ok=0
for url in "${URLS[@]}"; do
    if fetch "$url" "$ARCHIVE" 2>/dev/null && [ -s "$ARCHIVE" ]; then
        ok=1
        break
    fi
done
[ "$ok" = 1 ] || die "Download fehlgeschlagen. Pruefe Repository/Ref: $REPO / $REF"

mkdir -p "$TMP_DIR/src"
tar -xzf "$ARCHIVE" -C "$TMP_DIR/src" --strip-components=1 \
    || die "Archiv konnte nicht entpackt werden"
[ -f "$TMP_DIR/src/install.sh" ] || die "install.sh fehlt im Archiv"

# Sicherstellen, dass install.sh stdin von einem Terminal bekommt, falls sudo
# ein Passwort braucht (bei "curl | bash" ist stdin die Pipe).
run_install() {
    if [ -t 0 ]; then
        bash "$TMP_DIR/src/install.sh" "$@"
    elif [ -r /dev/tty ] && ( : </dev/tty ) 2>/dev/null; then
        bash "$TMP_DIR/src/install.sh" "$@" </dev/tty
    else
        bash "$TMP_DIR/src/install.sh" "$@" </dev/null
    fi
}

run_install "$@"
