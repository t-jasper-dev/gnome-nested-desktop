#!/usr/bin/env bash
# Richtet die echte gamescope-Session für GDM ein oder entfernt sie wieder.
#
# Aufruf:
#   ./setup-gamescope-session.sh [--autologin] [--no-autologin] [--dry-run]
#   ./setup-gamescope-session.sh --remove
#
# Die Session-Datei liegt systemweit unter /usr/share/wayland-sessions, weil
# GDM nur dort sucht. Das Session-Skript und die Konfiguration bleiben im
# Benutzerverzeichnis. Autologin wird in /etc/gdm/custom.conf eingetragen.
#
# Es werden keine laufenden Sitzungen beendet und GDM wird nicht neu gestartet.

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/gnome-nested-desktop"
ENV_FILE="$CONFIG_DIR/session.env"
SESSION_NAME="steam-nested"
SESSION_FILE="/usr/share/wayland-sessions/$SESSION_NAME.desktop"
GDM_CONF="/etc/gdm/custom.conf"
STEAM_NAME="GNOME (verschachtelt)"

AUTOLOGIN=0
AUTOLOGIN_SET=0
REMOVE=0
DRY_RUN=0

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mFEHLER:\033[0m %s\n' "$*" >&2; exit 1; }

run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '    [dry-run] %s\n' "$*"
    else
        "$@"
    fi
}

sudo_run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '    [dry-run] sudo %s\n' "$*"
    else
        sudo "$@"
    fi
}

usage() {
    cat <<'EOF'
Aufruf: ./setup-gamescope-session.sh [OPTIONEN]

  --autologin       GDM-Autologin für den aktuellen Benutzer aktivieren
  --no-autologin    GDM-Autologin deaktivieren, Session bleibt eingerichtet
  --remove          Session entfernen, AccountsService auf gnome zurücksetzen
                    und Autologin deaktivieren
  --dry-run         Nur anzeigen, was geändert würde
  -h, --help        Diese Hilfe anzeigen
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --autologin)    AUTOLOGIN=1; AUTOLOGIN_SET=1; shift ;;
        --no-autologin) AUTOLOGIN=0; AUTOLOGIN_SET=1; shift ;;
        --remove)       REMOVE=1; shift ;;
        --dry-run)      DRY_RUN=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              die "Unbekannte Option: $1" ;;
    esac
done

[ -f "$PROJECT_DIR/steam-nested-session" ] || die "steam-nested-session fehlt"
command -v gdbus >/dev/null 2>&1 || die "gdbus fehlt"
command -v python3 >/dev/null 2>&1 || die "python3 fehlt"
if [ "$DRY_RUN" = 0 ]; then
    command -v sudo >/dev/null 2>&1 || die "sudo fehlt"
fi

if ! systemctl is-active --quiet gdm.service 2>/dev/null; then
    warn "gdm.service ist nicht aktiv. Die Session-Datei wird trotzdem geschrieben;"
    warn "Autologin funktioniert nur mit GDM."
fi

find_shortcut_vdf() {
    local root f
    for root in \
        "${XDG_DATA_HOME:-$HOME/.local/share}/Steam" \
        "$HOME/.steam/steam" \
        "$HOME/.steam/root"; do
        for f in "$root"/userdata/*/config/shortcuts.vdf; do
            if [ -f "$f" ]; then
                printf '%s\n' "$f"
                return 0
            fi
        done
    done
    return 1
}

set_accounts_session() {
    local session="$1"
    local user_path="/org/freedesktop/Accounts/User$(id -u)"
    if sudo_run gdbus call --system \
            --dest org.freedesktop.Accounts \
            --object-path "$user_path" \
            --method org.freedesktop.Accounts.User.SetSession "$session"; then
        return 0
    fi

    warn "SetSession über AccountsService fehlgeschlagen, bearbeite die Datei direkt"
    local file="/var/lib/AccountsService/users/$USER"
    if [ "$DRY_RUN" = 0 ] && [ ! -f "$file" ]; then
        die "AccountsService-Datei fehlt: $file"
    fi
    sudo_run python3 - "$file" "$session" <<'PY'
import re
import sys

path, session = sys.argv[1:]
try:
    text = open(path, encoding="utf-8").read()
except FileNotFoundError:
    text = "[User]\n"
lines = text.splitlines()
out = []
in_user = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        in_user = stripped == "[User]"
        out.append(line)
        continue
    if in_user and re.match(r"\s*Session\s*=", line):
        continue
    out.append(line)
try:
    idx = next(i for i, line in enumerate(out) if line.strip() == "[User]")
except StopIteration:
    out.insert(0, "[User]")
    idx = 0
out[idx + 1:idx + 1] = [f"Session={session}"]
with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
PY
}

update_gdm_autologin() {
    local enable="$1"
    [ -f "$GDM_CONF" ] || die "$GDM_CONF fehlt"
    sudo_run cp -a "$GDM_CONF" "$GDM_CONF.bak.$(date +%Y%m%d-%H%M%S)"
    sudo_run python3 - "$GDM_CONF" "$USER" "$enable" <<'PY'
import re
import sys

path, user, enable = sys.argv[1:]
with open(path, encoding="utf-8") as f:
    lines = f.read().splitlines()

out = []
in_daemon = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        in_daemon = stripped == "[daemon]"
        out.append(line)
        continue
    if in_daemon and re.match(r"\s*AutomaticLogin(Enable)?\s*=", line):
        continue
    out.append(line)

if enable == "1":
    try:
        idx = next(i for i, line in enumerate(out) if line.strip() == "[daemon]")
    except StopIteration:
        out.insert(0, "[daemon]")
        idx = 0
    out[idx + 1:idx + 1] = [
        "AutomaticLoginEnable=True",
        f"AutomaticLogin={user}",
    ]

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
PY
}

install_session_file() {
    local tmp
    tmp=$(mktemp)
    cat >"$tmp" <<EOF
[Desktop Entry]
Name=Steam (verschachtelt)
Comment=GNOME (verschachtelt) in gamescope
Exec=$BIN_DIR/steam-nested-session
Type=Application
DesktopNames=gamescope
EOF
    if [ -f "$SESSION_FILE" ]; then
        sudo_run cp -a "$SESSION_FILE" "$SESSION_FILE.bak.$(date +%Y%m%d-%H%M%S)"
    fi
    sudo_run install -Dm644 "$tmp" "$SESSION_FILE"
    rm -f "$tmp"
}

write_session_env() {
    local vdf appid gameid
    vdf=$(find_shortcut_vdf) || die "Kein shortcuts.vdf gefunden. Zuerst ./install.sh ausführen."
    appid=$(python3 "$PROJECT_DIR/steam-shortcut.py" appid "$vdf" \
        --name "$STEAM_NAME" \
        --exe "$BIN_DIR/gnome-nested-desktop")
    gameid=$(python3 - "$appid" <<'PY'
import sys
appid = int(sys.argv[1])
print((appid << 32) | 0x02000000)
PY
)
    if [ "$DRY_RUN" = 1 ]; then
        printf '    [dry-run] schreibe %s (APPID=%s GAMEID=%s)\n' "$ENV_FILE" "$appid" "$gameid"
    else
        mkdir -p "$CONFIG_DIR"
        cat >"$ENV_FILE" <<EOF
APPID=$appid
GAMEID=$gameid
EOF
    fi
}

if [ "$REMOVE" = 1 ]; then
    say "Entferne gamescope-Session"
    if [ -f "$SESSION_FILE" ]; then
        sudo_run cp -a "$SESSION_FILE" "$SESSION_FILE.bak.$(date +%Y%m%d-%H%M%S)"
        sudo_run rm -f "$SESSION_FILE"
    fi
    set_accounts_session "gnome"
    if [ -f "$GDM_CONF" ]; then
        update_gdm_autologin 0
    else
        warn "$GDM_CONF fehlt, Autologin konnte nicht deaktiviert werden"
    fi
    run rm -f "$BIN_DIR/steam-nested-session"
    run rm -f "$ENV_FILE"
    run rm -f "$CONFIG_DIR/session-failed"
    say "Fertig"
    cat <<EOF

Session entfernt. AccountsService steht wieder auf "gnome".
Autologin ist deaktiviert.
Ein laufender gamescope-/Steam-Prozess wird nicht beendet.

Nächster Schritt: neu starten oder
  sudo systemctl restart gdm
EOF
    exit 0
fi

[ -f "$PROJECT_DIR/steam-shortcut.py" ] || die "steam-shortcut.py fehlt"
[ -x "$BIN_DIR/gnome-nested-desktop" ] || die "Wrapper fehlt: $BIN_DIR/gnome-nested-desktop (zuerst ./install.sh ausführen)"
command -v gamescope >/dev/null 2>&1 || die "gamescope fehlt"
command -v steam >/dev/null 2>&1 || die "steam fehlt"

say "Prüfe Shortcut und berechne GameID"
write_session_env

say "Installiere Session-Skript"
run install -d "$BIN_DIR"
run install -m755 "$PROJECT_DIR/steam-nested-session" "$BIN_DIR/steam-nested-session"

say "Installiere Session-Datei nach /usr/share/wayland-sessions"
install_session_file

say "Setze AccountsService-Session auf $SESSION_NAME"
set_accounts_session "$SESSION_NAME"

if [ "$AUTOLOGIN_SET" = 1 ]; then
    if [ "$AUTOLOGIN" = 1 ]; then
        say "Aktiviere GDM-Autologin für $USER"
        update_gdm_autologin 1
    else
        say "Deaktiviere GDM-Autologin"
        update_gdm_autologin 0
    fi
else
    say "GDM-Autologin bleibt unverändert"
fi

if [ "$AUTOLOGIN_SET" = 1 ]; then
    if [ "$AUTOLOGIN" = 1 ]; then
        autologin_text="aktiviert für $USER"
    else
        autologin_text="deaktiviert"
    fi
else
    autologin_text="nicht geändert"
fi

say "Fertig"
cat <<EOF

Session:        $SESSION_FILE
Session-Skript: $BIN_DIR/steam-nested-session
Konfiguration:  $ENV_FILE
GDM-Autologin:  $autologin_text

Beim nächsten Start wählt GDM die Session "Steam (verschachtelt)".
Mit Autologin startet sie ohne Anmeldung.

Rückweg (auch aus einer TTY mit Ctrl+Alt+F2):
  $PROJECT_DIR/setup-gamescope-session.sh --remove
  sudo systemctl restart gdm

Logs:
  ${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/steam-nested-session.log
  ${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gnome-nested-desktop.log
EOF
