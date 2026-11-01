# gnome-nested-desktop

Eine vollständige GNOME-Desktop-Sitzung als Steam-Shortcut – auch im Gaming Mode
(gamescope), randlos in voller Auflösung.

GNOME 49+ hat den alten `--nested`-Modus entfernt. Dieses Projekt nutzt das
offizielle **Mutter Devkit**: Eine eigene GNOME-Shell läuft in einer privaten
D-Bus-Session und wird über `mutter-devkit` in einem Fenster angezeigt.

## Funktionen

- Gaming Mode: Steam erkennt das Fenster über gamescopes Xwayland
  (`GDK_BACKEND=x11` nur für das Devkit-Fenster).
- Randlos in der vollen Monitorauflösung (Auflösung aus gamescopes Xwayland,
  `--monitor-size`, `_NET_WM_STATE_FULLSCREEN`).
- Skalierung standardmäßig wie in der laufenden GNOME-Sitzung; im Gaming Mode
  wird der zuletzt gesehene Faktor gecacht.
- Einstellungen und Bluetooth funktionieren in der verschachtelten Sitzung
  (`XDG_CURRENT_DESKTOP=GNOME`, `gsd-rfkill`).
- Dark/Light-Theme wird übernommen und folgt Änderungen der äußeren Sitzung
  (funktionierendes XDG-Portal + dconf-Sync).
- Minimieren/Maximieren/Schließen in Apps (`gsd-xsettings` für X11,
  `button-layout` für Wayland).
- Key-Up-Cleanup gegen hängende Pfeiltasten nach dem Start aus gamescope.
- Steam-Artwork (Grid, Hero, Logo, Header) und App-Icon.

## Voraussetzungen

- GNOME 51 (getestet mit mutter 51.0 auf Bazzite/Fedora)
- `gnome-shell`, `mutter`, `mutter-devkit`
- `gnome-settings-daemon`, `xdg-desktop-portal-gnome`,
  `gnome-control-center`, `nautilus`
- `gdbus`, `dbus-run-session`, `xdotool`, `xprop`, `xrandr`, `dconf`
- `python3`, `dnf`, `rpm2cpio`, `cpio` (nur für die lokale Devkit-Installation
  auf Fedora)

Die Pakete können mit `./install-deps.sh` aus dem System installiert werden
(siehe unten). Es wird kein Rootfs und kein Container mitgeliefert.

## Installation

### Schnellinstallation (curl oder wget)

Eine Zeile im Terminal – es wird nur ein temporäres Archiv geladen, entpackt
und `install.sh` gestartet. Das System selbst wird dabei nicht verändert.

```bash
curl -fsSL https://raw.githubusercontent.com/t-jasper-dev/gnome-nested-desktop/main/get.sh | bash
```

Alternativ mit `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/t-jasper-dev/gnome-nested-desktop/main/get.sh | bash
```

Optionen von `install.sh` lassen sich anhängen, z. B. ohne Steam-Artwork:

```bash
curl -fsSL https://raw.githubusercontent.com/t-jasper-dev/gnome-nested-desktop/main/get.sh | bash -s -- --skip-steam
```

Anderer Branch oder Tag:

```bash
curl -fsSL https://raw.githubusercontent.com/t-jasper-dev/gnome-nested-desktop/main/get.sh \
  | GND_REF=main bash
```

`get.sh` benötigt `curl` **oder** `wget` und `tar`. Bei `curl | bash` ist stdin
die Pipe; das Skript hängt stdin für `install.sh` an `/dev/tty`, damit `sudo`
bei Bedarf nach einem Passwort fragen kann.

Fehlen GNOME, `gnome-settings-daemon` oder das Portal noch komplett, vorher
einmal die Systempakete nachziehen (braucht `sudo`):

```bash
git clone https://github.com/t-jasper-dev/gnome-nested-desktop.git
cd gnome-nested-desktop
./install-deps.sh
```

Danach kann die Schnellinstallation oben laufen. Details zu den Paketen stehen
unter „Andere Distributionen“.

### Aus dem Checkout

```bash
git clone https://github.com/t-jasper-dev/gnome-nested-desktop.git
cd gnome-nested-desktop
./install.sh
```

Alternativ genügt `./get.sh` im Checkout – es ruft dasselbe `install.sh` auf.

`./install.sh` installiert ohne Root-Rechte:

- `~/.local/bin/gnome-nested-desktop`
- `~/.local/share/mutter-devkit/mutter-devkit` + Schema, falls noch nicht
  vorhanden (aus dem passenden `mutter-devkit`-RPM entpackt)
- `~/.local/share/mutter-devkit/gnome-nested.png` (Icon)
- `~/.local/share/applications/gnome-nested-desktop.desktop`
- Steam-Artwork, wenn ein Shortcut mit dem Ziel
  `gnome-nested-desktop` existiert

Optionen:

```text
--appid ID       Steam-AppID vorgeben, falls die automatische Erkennung fehlschlägt
--skip-devkit    Devkit-Installation überspringen
--skip-steam     Steam-Artwork überspringen
```

Falls die Devkit-Installation nicht gewünscht ist:

```bash
sudo dnf install mutter-devkit     # Fedora
sudo pacman -S mutter-devkit       # Arch
```

Der Wrapper bevorzugt das **System-Devkit**. Er sucht
`/usr/libexec/mutter-devkit`, `/usr/lib/mutter-devkit` und
`/usr/lib64/mutter-devkit`. Dann startet die GNOME-Shell den Devkit-Viewer
selbst und bekommt die Auflösung über `--devkit-args="--monitor-size WxH"`.
Ist kein System-Devkit
vorhanden (z. B. auf Bazzite), wird die kleine lokale Kopie unter
`~/.local/share/mutter-devkit` manuell mit `--monitor-size` gestartet.
Es wird nur das Devkit (ca. 250 KB) lokal gehalten, nicht GNOME oder ein
Rootfs.

## Andere Distributionen

`./install-deps.sh` installiert die GNOME-Bestandteile aus dem System:

| Distribution | Paketmanager |
|---|---|
| Fedora | `dnf` (bzw. `rpm-ostree` auf Bazzite) |
| Arch/CachyOS/Manjaro | `pacman` |
| Debian/Ubuntu | `apt` |
| openSUSE | `zypper` |

Das Script prüft vorher, was fehlt, und ändert nichts, wenn GNOME, gsd und
Portal schon vorhanden sind. Mit `--dry-run` werden nur die Befehle angezeigt.

**SteamOS:** Das Root-Dateisystem ist schreibgeschützt. Ein natives
Nachinstallieren von GNOME ist dort nicht update-fest. `install-deps.sh`
ändert SteamOS deshalb nicht automatisch. Für eine dauerhafte Lösung auf
SteamOS wäre ein Container oder ein eigener Rootfs nötig – für Arch/CachyOS,
Bazzite und Fedora reichen die normalen Systempakete.

Auf Arch ist `mutter-devkit` ein eigenes Paket in `extra` (derzeit 51.1) und
installiert `/usr/lib/mutter-devkit`. `gnome-settings-daemon` legt
`gsd-rfkill`/`gsd-xsettings` unter `/usr/lib` ab, das GNOME-Portal liegt unter
`/usr/lib/xdg-desktop-portal-gnome`. Der Wrapper sucht diese Pfade mit.

```bash
sudo pacman -S --needed gnome-shell mutter mutter-devkit \
  gnome-settings-daemon xdg-desktop-portal-gnome gnome-control-center \
  nautilus xdotool xorg-xprop xorg-xrandr xorg-xwininfo dconf \
  gsettings-desktop-schemas glib2 dbus
```

Auf Debian/Ubuntu ist `mutter-devkit` oft nicht paketiert.

## Steam-Shortcut

In Steam einen Nicht-Steam-Shortcut anlegen:

```text
Ziel:          ~/.local/bin/gnome-nested-desktop
Startordner:   ~/.local/bin
Startoptionen: (leer)
Name:          GNOME (verschachtelt)
Icon:          ~/.local/share/mutter-devkit/gnome-nested.png
```

Danach `./install.sh` erneut ausführen, damit das Artwork zur AppID kopiert
wird. Alternativ die AppID mit `--appid` angeben.

Die Bilder liegen unter:

```text
~/.local/share/Steam/userdata/<ID>/config/grid/
  <appid>p.png        (600x900)
  <appid>_hero.png    (3840x1240)
  <appid>_logo.png    (transparent)
  <appid>_header.png  (920x430)
  <appid>.png         (920x430, horizontales Grid)
```

Steam cacht Bibliotheksgrafiken teilweise – im Zweifel Steam bzw. den Gaming
Mode neu starten.

## Benutzung

```text
gnome-nested-desktop [--size WxH] [--scale N|host|auto|steam]

  --size WxH      Auflösung der verschachtelten Sitzung
                  (Gaming Mode: Standard = gamescope-Auflösung)
  --scale host    Standard: Faktor der laufenden GNOME-Sitzung
  --scale auto    GNOME wählt selbst
  --scale steam   Faktor der Steam-Oberfläche
  --scale N       fester Faktor (wird auf unterstützte Stufen gerundet)
```

Ohne `--size` im Desktop Mode öffnet das Devkit sein Standardfenster.

Das Laufzeit-Log liegt unter:

```text
/run/user/$UID/gnome-nested-desktop.log
```

Nützliche Zeilen:

```text
--- env: ... size=3840x2160 scale=1.5 scale_source=host
--- Skalierung 1.5 (angefragt: 1.5, Modus 3840x2160@0.000)
--- gsd-rfkill gestartet (pid=...)
--- gsd-xsettings gestartet (display=:2 pid=...)
```

## Wie es funktioniert

- Der Wrapper startet eine private `dbus-run-session` und darin
  `gnome-shell --wayland --devkit`.
- Das Devkit-Fenster wird im Gaming Mode über gamescopes Xwayland als
  X11-Client gestartet, randlos auf die volle Auflösung gelegt und die
  Skalierung über `org.gnome.Mutter.DisplayConfig` gesetzt.
- `XDG_CURRENT_DESKTOP=GNOME`, `gsd-rfkill` und ein funktionierendes
  XDG-Portal sorgen dafür, dass Einstellungen, Bluetooth und Dark Mode
  funktionieren.
- Ein kleiner Sync-Lauf spiegelt Theme-/Button-Änderungen der äußeren Sitzung
  in die private dconf-Instanz (dconf meldet Änderungen nicht über
  Session-Bus-Grenzen hinweg).
- `gsd-xsettings` wird nachgezogen, sobald das interne Xwayland startet.
- Nach dem Start werden einmalig Key-Ups für Navigation/Modifikatoren gesendet
  (gamescope verschluckt beim Shortcut-Start gelegentlich das Key-Up).

## Deinstallation

```bash
rm -f ~/.local/bin/gnome-nested-desktop
rm -f ~/.local/share/applications/gnome-nested-desktop.desktop
rm -f ~/.local/share/mutter-devkit/gnome-nested.png
rm -rf ~/.cache/gnome-nested-desktop
# optional, falls nur für dieses Projekt installiert:
# rm -f ~/.local/share/mutter-devkit/mutter-devkit
```

Steam-Artwork liegt im `config/grid`-Ordner der Steam-Userdata und kann dort
entfernt werden. Backups der überschriebenen Dateien enden auf
`.bak.<Zeitstempel>`.

## Lizenzhinweise

Das GNOME-Logo und die GNOME-Schriftmarke sind Marken der GNOME Foundation.
Die mitgelieferten Grafiken sind für die private Nutzung dieses Shortcuts
gedacht. Der Wrapper ist ein lokales Skript ohne Gewähr.
