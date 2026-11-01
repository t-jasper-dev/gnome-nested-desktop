#!/usr/bin/env bash
# gnome-nested-desktop installer
#
# Installiert:
#   - ~/.local/bin/gnome-nested-desktop
#   - ~/.local/share/mutter-devkit/mutter-devkit (+ GSettings-Schema), falls nötig
#   - ~/.local/share/mutter-devkit/gnome-nested.png
#   - ~/.local/share/applications/gnome-nested-desktop.desktop
#   - Steam-Non-Steam-Shortcut (shortcuts.vdf) inkl. Artwork
#
# Aufruf: ./install.sh [--appid ID] [--restart-steam] [--skip-shortcut]
#                      [--skip-devkit] [--skip-steam]
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
STEAM_NAME="GNOME (verschachtelt)"
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
SKIP_SHORTCUT=0
RESTART_STEAM=0
STEAM_WAS_RUNNING=0
STEAM_GAMEMODE=1

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
  --restart-steam  Steam für das Schreiben des Shortcuts automatisch beenden
                   und danach wieder starten (sonst wird gefragt)
  --skip-shortcut  Steam-Shortcut nicht anlegen/aktualisieren (Artwork wird
                   trotzdem installiert)
  --skip-devkit    mutter-devkit nicht prüfen/installieren
  --skip-steam     Steam-Shortcut, Artwork und Gaming-Mode-Starter nicht
                   installieren
  --steam-gamemode Steam-Standardstarter im Gaming Mode starten (Standard)
  --no-steam-gamemode
                   Steam-Standardstarter nicht ersetzen bzw. vorhandenen
                   Gaming-Mode-Starter entfernen
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
        --skip-shortcut)
            SKIP_SHORTCUT=1
            shift
            ;;
        --restart-steam)
            RESTART_STEAM=1
            shift
            ;;
        --steam-gamemode)
            STEAM_GAMEMODE=1
            shift
            ;;
        --no-steam-gamemode)
            STEAM_GAMEMODE=0
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
[ -f "$PROJECT_DIR/steam-gamemode" ] || die "steam-gamemode fehlt: $PROJECT_DIR/steam-gamemode"
[ -f "$PROJECT_DIR/steam-shortcut.py" ] || die "steam-shortcut.py fehlt: $PROJECT_DIR/steam-shortcut.py"
[ -d "$ASSET_DIR" ] || die "Assets fehlen: $ASSET_DIR"

say "Prüfe Abhängigkeiten"
for c in install gdbus xdotool xprop xrandr dbus-run-session python3 pgrep; do
    command -v "$c" >/dev/null 2>&1 || die "Befehl fehlt: $c"
done
command -v gnome-shell >/dev/null 2>&1 || die "gnome-shell fehlt"
[ -n "${XDG_RUNTIME_DIR:-}" ] || warn "XDG_RUNTIME_DIR ist nicht gesetzt"
if ! command -v gamescope >/dev/null 2>&1; then
    warn "gamescope fehlt. Der Steam-Shortcut startet dann ohne Gaming-Mode-"
    warn "Fenster; Steam Link/Remote Play kann die Sitzung so nicht aufnehmen."
    warn "Installation z. B. mit: sudo pacman -S gamescope  (oder dnf/apt)"
fi
if [ "$SKIP_STEAM" = 0 ] && [ "$STEAM_GAMEMODE" = 0 ] && command -v steam >/dev/null 2>&1; then
    warn "Der Steam-Standardstarter bleibt im Desktop Mode. Für Steam Link/Remote"
    warn "Play muss Steam im Gaming Mode laufen, sonst nimmt Steam ein internes"
    warn "Fenster auf und der Client bleibt schwarz."
fi

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

steam_roots() {
    printf '%s\n' \
        "${XDG_DATA_HOME:-$HOME/.local/share}/Steam" \
        "$HOME/.steam/steam" \
        "$HOME/.steam/root"
}

find_steam_config_dirs() {
    local root dir real seen=" "
    while IFS= read -r root; do
        [ -d "$root/userdata" ] || continue
        for dir in "$root"/userdata/*/config; do
            [ -d "$dir" ] || continue
            real=$(readlink -f -- "$dir" 2>/dev/null || printf '%s' "$dir")
            case "$seen" in
                *" $real "*) continue ;;
            esac
            seen="$seen$real "
            printf '%s\n' "$dir"
        done
    done < <(steam_roots)
}

steam_running() {
    pgrep -x steam >/dev/null 2>&1 && return 0
    pgrep -f '(^|/)ubuntu12_32/steam( |$)' >/dev/null 2>&1 && return 0
    pgrep -f 'steamwebhelper' >/dev/null 2>&1 && return 0
    return 1
}

steam_shutdown() {
    STEAM_WAS_RUNNING=1
    say "Beende Steam"
    if command -v steam >/dev/null 2>&1; then
        steam -shutdown >/dev/null 2>&1 || true
    fi
    local _
    for _ in $(seq 1 60); do
        steam_running || return 0
        sleep 0.5
    done
    warn "Steam läuft nach 30 s noch."
    return 1
}

prepare_steam_write() {
    steam_running || return 0
    warn "Steam läuft. Steam hält shortcuts.vdf im Speicher und überschreibt"
    warn "die Datei beim Beenden – der Shortcut ginge sonst wieder verloren."

    if [ "$RESTART_STEAM" = 1 ]; then
        steam_shutdown && return 0
        return 1
    fi

    if [ -r /dev/tty ] && ( : </dev/tty ) 2>/dev/null; then
        local answer=""
        printf 'Steam jetzt beenden, Shortcut schreiben und Steam danach neu starten? [J/n] ' >/dev/tty
        read -r answer </dev/tty || answer="n"
        case "$answer" in
            ""|j|J|ja|Ja|JA|y|Y|yes|Yes|YES)
                steam_shutdown && return 0
                return 1
                ;;
        esac
    fi

    warn "Shortcut wird übersprungen. Beende Steam und führe install.sh erneut"
    warn "aus (oder nutze --restart-steam). Artwork wird trotzdem vorbereitet."
    return 1
}

restart_steam_if_needed() {
    [ "$STEAM_WAS_RUNNING" = 1 ] || return 0
    say "Starte Steam neu"
    local launcher=steam
    if [ "$STEAM_GAMEMODE" = 1 ] && [ -x "$BIN_DIR/steam-gamemode" ]; then
        launcher="$BIN_DIR/steam-gamemode"
    fi
    if command -v setsid >/dev/null 2>&1; then
        setsid "$launcher" >/dev/null 2>&1 </dev/null &
    else
        nohup "$launcher" >/dev/null 2>&1 </dev/null &
    fi
}

install_steam_gamemode() {
    [ "$SKIP_STEAM" = 1 ] && { say "Steam-Gaming-Mode-Starter übersprungen"; return; }

    local dst="$APP_DIR/steam.desktop"
    if [ "$STEAM_GAMEMODE" = 0 ]; then
        if [ -f "$dst" ] && grep -q "$BIN_DIR/steam-gamemode" "$dst" 2>/dev/null; then
            say "Entferne Steam-Gaming-Mode-Starter"
            backup "$dst"
            rm -f "$dst"
            update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
        fi
        return
    fi

    if ! command -v steam >/dev/null 2>&1; then
        warn "Steam nicht gefunden, Gaming-Mode-Starter wird nicht eingerichtet"
        return
    fi

    say "Installiere Steam-Gaming-Mode-Starter"
    install -d "$BIN_DIR"
    backup "$BIN_DIR/steam-gamemode"
    install -m755 "$PROJECT_DIR/steam-gamemode" "$BIN_DIR/steam-gamemode"

    # Den systemweiten Steam-Eintrag als benutzerspezifische Kopie überschreiben
    # und nur den Programmaufruf ersetzen. Aktionen wie "Store" oder "Library"
    # behalten ihre Argumente und laufen ebenfalls über den Starter.
    local src=/usr/share/applications/steam.desktop
    install -d "$APP_DIR"
    backup "$dst"
    if [ -f "$src" ]; then
        python3 - "$src" "$dst" "$BIN_DIR/steam-gamemode" <<'PY'
import re
import sys

src, dst, launcher = sys.argv[1:]
text = open(src, encoding="utf-8").read()
text = re.sub(
    r"(?m)^Exec=(?:/usr/bin/|/usr/local/bin/)?steam(?=\s|$)",
    lambda _match: f"Exec={launcher}",
    text,
)
with open(dst, "w", encoding="utf-8") as f:
    f.write(text)
PY
    else
        cat >"$dst" <<EOF
[Desktop Entry]
Name=Steam
Comment=Steam im Gaming Mode (gamescope)
Exec=$BIN_DIR/steam-gamemode %U
Icon=steam
Terminal=false
Type=Application
Categories=Network;FileTransfer;Game;
MimeType=x-scheme-handler/steam;x-scheme-handler/steamlink;
EOF
    fi
    chmod 644 "$dst"
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
    say "Steam-Standardstarter -> $BIN_DIR/steam-gamemode"
}

install_steam_shortcut() {
    [ "$SKIP_STEAM" = 1 ] && { say "Steam-Shortcut übersprungen"; return; }
    [ "$SKIP_SHORTCUT" = 1 ] && { say "Steam-Shortcut übersprungen"; return; }

    local config_dirs=()
    mapfile -t config_dirs < <(find_steam_config_dirs)
    if [ ${#config_dirs[@]} -eq 0 ]; then
        warn "Keine Steam-Userdata gefunden. Steam einmal starten und einloggen,"
        warn "danach install.sh erneut ausführen."
        return
    fi

    local write_ok=0
    prepare_steam_write && write_ok=1

    local config vdf appid args
    for config in "${config_dirs[@]}"; do
        [ "$write_ok" = 1 ] || continue
        vdf="$config/shortcuts.vdf"
        say "Lege Steam-Shortcut an"
        backup "$vdf"
        args=(
            --name "$STEAM_NAME"
            --exe "$BIN_DIR/gnome-nested-desktop"
            --startdir "$BIN_DIR"
            --icon "$MDK_DIR/gnome-nested.png"
            --launch-options "--gamescope"
        )
        [ -n "$APPID" ] && args+=(--appid "$APPID")
        if appid=$(python3 "$PROJECT_DIR/steam-shortcut.py" add "$vdf" "${args[@]}" 2>&1); then
            say "Steam-Shortcut AppID $appid"
        else
            warn "Shortcut konnte nicht geschrieben werden: $appid"
        fi
    done
}

install_steam_art() {
    [ "$SKIP_STEAM" = 1 ] && { say "Steam-Artwork übersprungen"; return; }
    say "Installiere Steam-Artwork"
    local config_dirs=() config vdf appid grid found=0
    mapfile -t config_dirs < <(find_steam_config_dirs)
    for config in "${config_dirs[@]}"; do
        vdf="$config/shortcuts.vdf"
        appid="$APPID"
        if [ -z "$appid" ]; then
            appid=$(find_appid "$vdf" 2>/dev/null || true)
        fi
        if [ -z "$appid" ]; then
            # Noch kein Eintrag (z. B. Steam lief noch): dieselbe AppID, die
            # der Shortcut beim nächsten Lauf bekommt, schon jetzt verwenden.
            appid=$(python3 "$PROJECT_DIR/steam-shortcut.py" appid "$vdf" \
                --name "$STEAM_NAME" \
                --exe "$BIN_DIR/gnome-nested-desktop" 2>/dev/null || true)
        fi
        [ -n "$appid" ] || continue
        grid="$config/grid"
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
        warn "Kein Steam-Userdata-Ordner gefunden – Artwork nicht installiert."
    else
        warn "Steam nach dem Schreiben neu starten, damit Shortcut und Bilder erscheinen."
    fi
}

install_steam_gamemode
install_steam_shortcut
install_steam_art
restart_steam_if_needed

say "Fertig"
cat <<EOF

Wrapper:  $BIN_DIR/gnome-nested-desktop
Icon:     $MDK_DIR/gnome-nested.png
Desktop:  $APP_DIR/gnome-nested-desktop.desktop
Log:      ${XDG_RUNTIME_DIR:-/tmp}/gnome-nested-desktop.log

Steam-Shortcut:
  Wird automatisch in shortcuts.vdf angelegt (Name: $STEAM_NAME).
  Ziel:          $BIN_DIR/gnome-nested-desktop
  Startordner:   $BIN_DIR
  Startoptionen: --gamescope
  Icon:          $MDK_DIR/gnome-nested.png

  --gamescope startet die Sitzung in einer eigenen gamescope-Instanz. Für
  Steam Link/Remote Play muss Steam im Gaming Mode laufen; dort wird das
  vorhandene gamescope mitbenutzt. Im Desktop Mode funktioniert das Fenster
  lokal, Steam nimmt aber ein internes Fenster auf (Client bleibt schwarz).
  Für eine kleinere Stream-Auflösung z. B.: --gamescope --size 1920x1080 --scale 1

  Falls Steam beim Installieren lief und nicht beendet wurde:
  Steam beenden und install.sh erneut ausführen.

Skalierung:
  Standard ist derselbe Faktor wie die laufende GNOME-Sitzung.
  Optional in den Startoptionen: --scale 2  oder  --scale steam
  (im Gaming Mode wird der zuletzt gesehene Host-Faktor gecacht).

Hinweis: Die Einstellungen-, Bluetooth-, Theme- und Skalierungsfixes sind
im Wrapper enthalten. Details stehen in der README.md.
EOF

if [ "$SKIP_STEAM" = 0 ] && [ "$STEAM_GAMEMODE" = 1 ] && [ -x "$BIN_DIR/steam-gamemode" ]; then
    cat <<EOF

Steam-Starter:
  Der normale Steam-Eintrag startet im Gaming Mode (Big Picture/gamescope):
    $BIN_DIR/steam-gamemode
  Desktop-Eintrag: $APP_DIR/steam.desktop
  Läuft Steam bereits im Desktop Mode, wird es nicht automatisch beendet.
  Zum Wechsel: steam -shutdown, danach Steam neu starten.
  Abschalten: ./install.sh --no-steam-gamemode
EOF
fi
