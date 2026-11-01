#!/usr/bin/env bash
# gnome-nested-desktop installer
#
# Installiert:
#   - ~/.local/bin/gnome-nested-desktop
#   - ~/.local/share/mutter-devkit/mutter-devkit (+ GSettings-Schema), falls nötig
#   - ~/.local/share/mutter-devkit/gnome-nested.png
#   - ~/.local/share/applications/gnome-nested-desktop.desktop
#   - Steam-Artwork im userdata-Grid-Ordner, wenn ein Shortcut existiert
#
# Aufruf: ./install.sh [--appid ID] [--skip-devkit] [--skip-steam]
#
# Das Skript braucht keine Root-Rechte. Wenn mutter-devkit fehlt, wird das
# passende RPM mit "dnf download" geholt und nach ~/.local/share/mutter-devkit
# entpackt. Alternativ vorher: sudo dnf install mutter-devkit

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ASSET_DIR="$PROJECT_DIR/assets"

BIN_DIR="$HOME/.local/bin"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
MDK_DIR="$DATA_HOME/mutter-devkit"
APP_DIR="$DATA_HOME/applications"
STEAM_USERDATA="$HOME/.local/share/Steam/userdata"
SYSTEM_DEVKIT=""
for candidate in /usr/libexec/mutter-devkit /usr/lib/mutter-devkit /usr/lib64/mutter-devkit; do
    if [ -x "$candidate" ]; then
        SYSTEM_DEVKIT="$candidate"
        break
    fi
done

APPID=""
SKIP_DEVKIT=0
SKIP_STEAM=0

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mFEHLER:\033[0m %s\n' "$*" >&2; exit 1; }

backup() {
    [ -e "$1" ] || return 0
    local bak="$1.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a -- "$1" "$bak"
    printf '    Backup: %s\n' "$bak"
}

usage() {
    cat <<'EOF'
Aufruf: ./install.sh [OPTIONEN]

  --appid ID       Steam-AppID des Shortcuts vorgeben (sonst automatisch
                   anhand des Shortcut-Ziels gnome-nested-desktop gesucht)
  --skip-devkit    mutter-devkit nicht prüfen/installieren
  --skip-steam     Steam-Artwork nicht installieren
  -h, --help       Diese Hilfe anzeigen
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --appid)
            [ $# -ge 2 ] || die "--appid braucht einen Wert"
            APPID="$2"
            shift 2
            ;;
        --appid=*)
            APPID="${1#*=}"
            shift
            ;;
        --skip-devkit)
            SKIP_DEVKIT=1
            shift
            ;;
        --skip-steam)
            SKIP_STEAM=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unbekannte Option: $1"
            ;;
    esac
done

[ -f "$PROJECT_DIR/gnome-nested-desktop" ] || die "Wrapper fehlt: $PROJECT_DIR/gnome-nested-desktop"
[ -d "$ASSET_DIR" ] || die "Assets fehlen: $ASSET_DIR"

say "Prüfe Abhängigkeiten"
for c in install gdbus xdotool xprop xrandr dbus-run-session python3; do
    command -v "$c" >/dev/null 2>&1 || die "Befehl fehlt: $c"
done
command -v gnome-shell >/dev/null 2>&1 || die "gnome-shell fehlt"
[ -n "${XDG_RUNTIME_DIR:-}" ] || warn "XDG_RUNTIME_DIR ist nicht gesetzt"

ensure_devkit_schema() {
    local schema="$MDK_DIR/schemas/org.gnome.mutter.devkit.gschema.xml"
    if [ ! -f "$schema" ] && [ -f /usr/share/glib-2.0/schemas/org.gnome.mutter.devkit.gschema.xml ]; then
        install -Dm644 /usr/share/glib-2.0/schemas/org.gnome.mutter.devkit.gschema.xml "$schema"
    fi
    if [ -f "$schema" ]; then
        command -v glib-compile-schemas >/dev/null 2>&1 || die "glib-compile-schemas fehlt"
        glib-compile-schemas "$MDK_DIR/schemas"
    else
        warn "GSettings-Schema für mutter-devkit fehlt; das Devkit startet evtl. mit Warnung"
    fi
}

install_devkit() {
    [ "$SKIP_DEVKIT" = 1 ] && { say "Devkit-Prüfung übersprungen"; return; }
    if [ -x "$SYSTEM_DEVKIT" ]; then
        say "System-mutter-devkit vorhanden: $SYSTEM_DEVKIT"
        return
    fi
    if [ -x "$MDK_DIR/mutter-devkit" ]; then
        say "Lokales mutter-devkit vorhanden"
        ensure_devkit_schema
        return
    fi
    say "Lade passendes mutter-devkit-Paket"
    command -v dnf >/dev/null 2>&1 || die "Kein mutter-devkit gefunden. Auf Arch: sudo pacman -S mutter-devkit; auf Fedora: sudo dnf install mutter-devkit"
    local tmp rpmfile mutter_ver
    tmp=$(mktemp -d)
    mutter_ver=$(rpm -q --qf '%{VERSION}' mutter 2>/dev/null || true)
    if [ -n "$mutter_ver" ] && dnf download --destdir "$tmp" "mutter-devkit-${mutter_ver}" >/dev/null 2>&1; then
        :
    elif dnf download --destdir "$tmp" mutter-devkit >/dev/null 2>&1; then
        :
    else
        rm -rf "$tmp"
        die "Konnte mutter-devkit nicht herunterladen. Alternativ: sudo dnf install mutter-devkit"
    fi
    rpmfile=$(find "$tmp" -maxdepth 1 -name 'mutter-devkit-*.rpm' -print -quit)
    [ -n "$rpmfile" ] || { rm -rf "$tmp"; die "mutter-devkit-RPM nicht gefunden"; }
    command -v rpm2cpio >/dev/null 2>&1 || { rm -rf "$tmp"; die "rpm2cpio fehlt"; }
    command -v cpio >/dev/null 2>&1 || { rm -rf "$tmp"; die "cpio fehlt"; }
    ( cd "$tmp" && rpm2cpio "$rpmfile" | cpio -idm --quiet )
    install -Dm755 "$tmp/usr/libexec/mutter-devkit" "$MDK_DIR/mutter-devkit"
    if [ -f "$tmp/usr/share/glib-2.0/schemas/org.gnome.mutter.devkit.gschema.xml" ]; then
        install -Dm644 "$tmp/usr/share/glib-2.0/schemas/org.gnome.mutter.devkit.gschema.xml" \
            "$MDK_DIR/schemas/org.gnome.mutter.devkit.gschema.xml"
    fi
    rm -rf "$tmp"
    ensure_devkit_schema
    say "mutter-devkit nach $MDK_DIR installiert"
}

install_devkit

say "Installiere Wrapper nach $BIN_DIR"
install -d "$BIN_DIR"
backup "$BIN_DIR/gnome-nested-desktop"
install -m755 "$PROJECT_DIR/gnome-nested-desktop" "$BIN_DIR/gnome-nested-desktop"

say "Installiere Icon"
install -d "$MDK_DIR"
backup "$MDK_DIR/gnome-nested.png"
install -m644 "$ASSET_DIR/icon.png" "$MDK_DIR/gnome-nested.png"

say "Installiere Desktop-Eintrag"
install -d "$APP_DIR"
backup "$APP_DIR/gnome-nested-desktop.desktop"
python3 - "$PROJECT_DIR/gnome-nested-desktop.desktop.in" \
    "$APP_DIR/gnome-nested-desktop.desktop" \
    "$HOME" "$MDK_DIR/gnome-nested.png" <<'PY'
import sys
src, dst, home, icon = sys.argv[1:]
text = open(src, encoding="utf-8").read()
text = text.replace("@HOME@", home).replace("@ICON@", icon)
with open(dst, "w", encoding="utf-8") as f:
    f.write(text)
PY
chmod 644 "$APP_DIR/gnome-nested-desktop.desktop"
update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true

find_appid() {
    python3 - "$1" "gnome-nested-desktop" <<'PY'
import struct
import sys

vdf, needle = sys.argv[1], sys.argv[2].encode()
data = open(vdf, "rb").read()
# Erst exakt nach dem AppName suchen, danach nach dem Exe-Pfad.
markers = [b"AppName\x00" + needle + b"\x00", needle]
for marker in markers:
    pos = data.find(marker)
    while pos != -1:
        apos = data.rfind(b"\x02appid\x00", 0, pos)
        if apos != -1 and apos + 11 <= len(data):
            print(struct.unpack_from("<I", data, apos + 7)[0])
            sys.exit(0)
        pos = data.find(marker, pos + 1)
sys.exit(1)
PY
}

install_steam_art() {
    [ "$SKIP_STEAM" = 1 ] && { say "Steam-Artwork übersprungen"; return; }
    say "Installiere Steam-Artwork"
    local found=0 vdf appid grid
    for vdf in "$STEAM_USERDATA"/*/config/shortcuts.vdf; do
        [ -f "$vdf" ] || continue
        appid="$APPID"
        if [ -z "$appid" ]; then
            appid=$(find_appid "$vdf" || true)
        fi
        [ -n "$appid" ] || continue
        grid="$(dirname -- "$vdf")/grid"
        install -d "$grid"
        backup "$grid/${appid}p.png"
        backup "$grid/${appid}_hero.png"
        backup "$grid/${appid}_logo.png"
        backup "$grid/${appid}_header.png"
        backup "$grid/${appid}.png"
        install -m644 "$ASSET_DIR/grid.png"   "$grid/${appid}p.png"
        install -m644 "$ASSET_DIR/hero.png"   "$grid/${appid}_hero.png"
        install -m644 "$ASSET_DIR/logo.png"   "$grid/${appid}_logo.png"
        install -m644 "$ASSET_DIR/header.png" "$grid/${appid}_header.png"
        install -m644 "$ASSET_DIR/header.png" "$grid/${appid}.png"
        say "Artwork für AppID $appid -> $grid"
        found=1
    done
    if [ "$found" = 0 ]; then
        warn "Kein Steam-Shortcut gefunden. Lege einen Shortcut an:"
        warn "  Ziel:          $BIN_DIR/gnome-nested-desktop"
        warn "  Startordner:   $BIN_DIR"
        warn "  Startoptionen: (leer)"
        warn "Danach install.sh erneut ausführen oder --appid <ID> angeben."
    else
        warn "Steam ggf. neu starten, damit die neuen Bilder geladen werden."
    fi
}

install_steam_art

say "Fertig"
cat <<EOF

Wrapper:  $BIN_DIR/gnome-nested-desktop
Icon:     $MDK_DIR/gnome-nested.png
Desktop:  $APP_DIR/gnome-nested-desktop.desktop
Log:      ${XDG_RUNTIME_DIR:-/tmp}/gnome-nested-desktop.log

Steam-Shortcut:
  Ziel:          $BIN_DIR/gnome-nested-desktop
  Startordner:   $BIN_DIR
  Startoptionen: (leer)
  Icon:          $MDK_DIR/gnome-nested.png

Skalierung:
  Standard ist derselbe Faktor wie die laufende GNOME-Sitzung.
  Optional in den Startoptionen: --scale 2  oder  --scale steam
  (im Gaming Mode wird der zuletzt gesehene Host-Faktor gecacht).

Hinweis: Die Einstellungen-, Bluetooth-, Theme- und Skalierungsfixes sind
im Wrapper enthalten. Details stehen in der README.md.
EOF
