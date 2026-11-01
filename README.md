# gnome-nested-desktop

Eine vollständige GNOME-Desktop-Sitzung als Steam-Shortcut – im Gaming Mode
(gamescope) randlos in voller Auflösung und für Steam Link/Remote Play
übertragbar. Im Desktop Mode startet der Shortcut die Sitzung in einer eigenen
gamescope-Instanz für die lokale Anzeige.

GNOME 49+ hat den alten `--nested`-Modus entfernt. Dieses Projekt nutzt das
offizielle **Mutter Devkit**: Eine eigene GNOME-Shell läuft in einer privaten
D-Bus-Session und wird über `mutter-devkit` in einem Fenster angezeigt.

## Funktionen

- Gaming Mode: Steam erkennt das Fenster über gamescopes Xwayland
  (`GDK_BACKEND=x11` nur für das Devkit-Fenster).
- Startet aus Steam automatisch in einer eigenen gamescope-Instanz, wenn noch
  keine Gaming-Mode-Sitzung läuft (lokale Anzeige im Desktop Mode).
- Steam Link/Remote Play: Steam im Gaming Mode starten, damit Steam die richtige
  Aufnahmequelle erhält (siehe [Steam Link / Remote Play](#steam-link--remote-play)).
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
- Legt den Steam-Shortcut automatisch an (`shortcuts.vdf`) und installiert das
  Artwork (Grid, Hero, Logo, Header) sowie das App-Icon.
- Ersetzt den normalen Steam-Starter standardmäßig durch `steam-gamemode`, damit
  Steam Link die Sitzung aufnehmen kann (abschaltbar mit
  `--no-steam-gamemode`).
- Optional echte gamescope-Session: GDM bootet mit `--gamescope-session` direkt
  in die verschachtelte GNOME-Sitzung, ohne äußeres GNOME.

## Voraussetzungen

- GNOME 51 (getestet mit mutter 51.0 auf Bazzite/Fedora)
- `gnome-shell`, `mutter`, `mutter-devkit`
- `gnome-settings-daemon`, `xdg-desktop-portal-gnome`,
  `gnome-control-center`, `nautilus`
- `gdbus`, `dbus-run-session`, `xdotool`, `xprop`, `xrandr`, `dconf`,
  `pgrep` (procps)
- `gamescope` (für Gaming Mode und Steam Link/Remote Play)
- `python3`, `dnf`, `rpm2cpio`, `cpio` (nur für die lokale Devkit-Installation
  auf Fedora)

Die Pakete können mit `./install-deps.sh` aus dem System installiert werden
(siehe unten). Es wird kein Rootfs und kein Container mitgeliefert.

## Installation

### Schnellinstallation (curl oder wget)

Eine Zeile im Terminal – es wird nur ein temporäres Archiv geladen, entpackt
und `install.sh` gestartet. Das System selbst wird dabei nicht verändert.
`install.sh` legt Wrapper, Desktop-Eintrag und den Steam-Shortcut an.

Läuft Steam während der Installation, fragt das Skript, ob Steam kurz beendet
werden darf. Das ist nötig, weil Steam `shortcuts.vdf` beim Beenden aus dem
Speicher neu schreibt und den neuen Eintrag sonst wieder verwerfen würde.
Danach wird Steam automatisch neu gestartet.

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
- Steam-Shortcut in `shortcuts.vdf` inkl. Artwork (falls Steam-Userdata
  vorhanden; Steam wird bei Bedarf kurz beendet und neu gestartet)

Optionen:

```text
--appid ID        Steam-AppID vorgeben, falls die automatische Erkennung fehlschlägt
--restart-steam   Steam ohne Rückfrage beenden und nach dem Schreiben neu starten
--skip-shortcut   Steam-Shortcut nicht anlegen (Artwork wird trotzdem installiert)
--skip-devkit     Devkit-Installation überspringen
--skip-steam      Steam-Shortcut und Artwork überspringen
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

`install.sh` legt den Nicht-Steam-Shortcut automatisch an:

```text
Name:          GNOME (verschachtelt)
Ziel:          ~/.local/bin/gnome-nested-desktop
Startordner:   ~/.local/bin
Startoptionen: --gamescope
Icon:          ~/.local/share/mutter-devkit/gnome-nested.png
```

`--gamescope` startet die Sitzung in einer eigenen gamescope-Instanz, falls
noch keine Gaming-Mode-Sitzung läuft. Im Desktop Mode dient das der lokalen
Anzeige; für Steam Link/Remote Play muss Steam selbst im Gaming Mode laufen
(siehe unten). In einer echten Gaming-Mode-Sitzung ist die Option wirkungslos,
dort wird das vorhandene gamescope mitbenutzt (keine Verschachtelung).

Der Eintrag landet in `~/.local/share/Steam/userdata/<ID>/config/shortcuts.vdf`.
Die AppID wird deterministisch aus Zielpfad und Name berechnet; ein erneuter
Lauf legt keinen doppelten Eintrag an, sondern aktualisiert den vorhandenen.
Für Flatpak-Steam wird der Shortcut nicht automatisch angelegt (dort müsste
das Ziel über `flatpak-spawn --host` laufen); native Steam-Installationen
werden unterstützt.

**Wichtig:** Steam muss beim Schreiben beendet sein, weil Steam die Datei beim
Beenden aus dem Speicher überschreibt. Läuft Steam, fragt `install.sh` nach
(Enter = ja) und startet Steam nach dem Schreiben wieder. Ohne Terminal oder
mit `n` wird der Shortcut übersprungen; dann einfach Steam beenden und
`install.sh` erneut ausführen. Mit `--restart-steam` geht das ohne Rückfrage.

Nach dem Schreiben Steam neu starten, damit Shortcut und Artwork erscheinen.

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

Falls der automatische Eintrag nicht gewünscht ist, `--skip-shortcut`
(Artwork bleibt) oder `--skip-steam` (beides aus) verwenden.

## Steam standardmäßig im Gaming Mode

`install.sh` installiert `~/.local/bin/steam-gamemode` und legt damit einen
benutzerspezifischen Steam-Eintrag unter
`~/.local/share/applications/steam.desktop` an. Der normale Steam-Starter
startet dadurch Big Picture in einer gamescope-Sitzung. Das ist die
Voraussetzung dafür, dass Steam Link den verschachtelten Desktop aufnehmen
kann.

- Läuft Steam bereits, wird nur die vorhandene Instanz geöffnet. Für den
  Wechsel in den Gaming Mode Steam vorher beenden: `steam -shutdown`, danach
  Steam neu starten.
- In einer echten Gaming-Mode-Sitzung erkennt der Starter das vorhandene
  gamescope und startet Steam ohne weitere Verschachtelung.
- Ohne gamescope startet Steam normal im Desktop Mode.
- Der Starter aktiviert das gamescope-Fenster nach dem Start. Das ist wichtig,
  wenn die Tastatur direkt am PC benutzt wird: Ohne Fokus landet `Shift+Tab` in
  der äußeren GNOME-Shell und das Steam-Overlay öffnet nicht. Alternativ den
  Steam-Button im Steam-Link-Client verwenden. Geht der Fokus später verloren,
  einmal in das gamescope-Fenster klicken.
- Abschalten und den systemweiten Eintrag wiederherstellen:
  `./install.sh --no-steam-gamemode`
- Kleinere Ausgabegröße fürs Streaming:
  `STEAM_GAMEMODE_SIZE=1920x1080 steam-gamemode`

Der Starter lässt sich auch direkt aufrufen:

```text
steam-gamemode
steam-gamemode steam://open/bigpicture
```

## Echte gamescope-Session (Boot direkt in die verschachtelte Sitzung)

Statt GNOME zu starten und Steam per Autostart in ein gamescope-Fenster zu
legen, kann GDM direkt eine echte gamescope-Session starten:

```text
GDM (Autologin)
  → /usr/share/wayland-sessions/steam-nested.desktop
  → ~/.local/bin/steam-nested-session
  → gamescope (DRM) + Steam Gaming Mode
  → Shortcut "GNOME (verschachtelt)"
  → verschachtelte GNOME-Sitzung fullscreen
```

Es gibt dabei keine äußere GNOME-Sitzung. Die verschachtelte GNOME-Shell ist
das sichtbare System; Steam läuft als Gaming-Mode-Session darunter.

Einrichten:

```bash
./install.sh --gamescope-session --autologin
```

Ohne Autologin (Session muss im GDM ausgewählt werden):

```bash
./install.sh --gamescope-session
```

Das Setup legt an:

```text
/usr/share/wayland-sessions/steam-nested.desktop   (systemweit, sudo)
~/.local/bin/steam-nested-session                  (Session-Skript)
~/.config/gnome-nested-desktop/session.env         (AppID/GameID)
```

Zusätzlich wird die AccountsService-Session auf `steam-nested` gesetzt und –
mit `--autologin` – GDM-Autologin in `/etc/gdm/custom.conf` aktiviert. GDM
wird dabei nicht automatisch neu gestartet.

Nach dem nächsten Boot startet die Session automatisch. Wird Steam beendet,
startet das Session-Skript es nach 5 Sekunden neu; das verhindert eine
Autologin-Schleife. Nach drei schnellen Fehlstarts bleibt die Session mit einer
Markierung `~/.config/gnome-nested-desktop/session-failed` stehen, statt in
einer Login-Schleife zu landen. Zum dauerhaften Verlassen:

```bash
./setup-gamescope-session.sh --remove
sudo systemctl restart gdm
```

Aus einer Textkonsole (z. B. `Ctrl+Alt+F2`) funktioniert derselbe Befehl mit
absolutem Pfad:

```bash
/home/tobias/Projekte/gnome-nested-desktop/setup-gamescope-session.sh --remove
```

Danach ist die normale GNOME-Session wieder der Standard. Die Session-Datei
bleibt als Backup erhalten; die aktuelle GNOME-Session wird nicht beendet.

Logs:

```text
/run/user/$UID/steam-nested-session.log
/run/user/$UID/gnome-nested-desktop.log
```

Hinweise:

- Autologin entsperrt die Sitzung ohne Passwort.
- Der GNOME-Keyring ist bei Autologin eventuell nicht entsperrt; Steam
  `AutoLogin=1` sollte trotzdem funktionieren, muss aber getestet werden.
- Die echte gamescope-Session braucht `sudo` für die Session-Datei, die
  AccountsService-Session und optional GDM-Autologin.
- `steam-gamemode` bleibt für den Desktop Mode erhalten und wird für diese
  Session nicht benötigt.

## Steam Link / Remote Play

Auf dem Host muss Remote Play aktiviert sein (Steam → Einstellungen → Remote
Play → Remote Play aktivieren) und Steam angemeldet sein. Auf dem Client in
der Bibliothek den Shortcut **GNOME (verschachtelt)** starten.

**Voraussetzung: Steam muss im Gaming Mode laufen.** Nur dort bekommt Steam die
richtige Aufnahmequelle: Es erkennt die gamescope-Sitzung und nimmt das Fenster
der verschachtelten Sitzung auf. Der Shortcut benutzt dann das vorhandene
gamescope (keine zweite Instanz). Der mitinstallierte Steam-Starter
(`steam-gamemode`) erledigt das standardmäßig; siehe
[Steam standardmäßig im Gaming Mode](#steam-standardmäßig-im-gaming-mode).

Läuft Steam dagegen im Desktop Mode, erkennt Steam zwar die vom Shortcut
gestartete gamescope-Instanz, wählt für die Aufnahme aber ein internes
1×1-Fenster statt des sichtbaren Fensters. Das Bild am Steam-Link-Client bleibt
dann schwarz, obwohl die Sitzung auf dem Host korrekt dargestellt wird.

Steam im Gaming Mode starten, z. B. auf einer Textkonsole:

```text
steam -shutdown
gamescope -f -- steam -gamepadui
```

Aus einer laufenden GNOME-Sitzung heraus geht dasselbe verschachtelt:

```text
steam -shutdown
gamescope --backend sdl -f -e -- steam -gamepadui
```

Der Shortcut läuft mit `--gamescope`. In einer echten Gaming-Mode-Sitzung ist
die Option wirkungslos. Im Desktop Mode startet der Wrapper damit eine eigene
gamescope-Instanz mit SDL/X11-Ausgabe; das ist nur für die lokale Anzeige
gedacht und ersetzt keine Gaming-Mode-Sitzung. Ohne gamescope bricht die
Aufnahme mit `k_ECaptureFailedReasonPipewireRequired` ab.

Die verschachtelte GNOME-Sitzung läuft unabhängig von der lokal angemeldeten
Sitzung. Maus und Tastatur werden durchgereicht. Für einen Controller lässt
sich in den Steam-Einstellungen des Shortcuts ein Desktop-Layout zuweisen; die
verschachtelte Sitzung selbst braucht dafür keine besondere Konfiguration.

Standardmäßig wird die physische Monitorauflösung und die Skalierung der
laufenden GNOME-Sitzung übernommen. Für eine kleinere, leichter zu kodierende
Stream-Auflösung die Startoptionen des Shortcuts anpassen, z. B.:

```text
--gamescope --size 1920x1080 --scale 1
```

Fehlt `gamescope`, startet der Shortcut weiterhin als normales Fenster, ist aber
für Steam Link nicht aufnehmbar. Installation z. B. mit
`sudo pacman -S gamescope`, `sudo dnf install gamescope` oder
`sudo apt install gamescope` (siehe auch `./install-deps.sh`).

## Benutzung

```text
gnome-nested-desktop [--size WxH] [--scale N|host|auto|steam] [--gamescope]

  --size WxH      Auflösung der verschachtelten Sitzung
                  (Gaming Mode: Standard = gamescope-Auflösung)
  --scale host    Standard: Faktor der laufenden GNOME-Sitzung
  --scale auto    GNOME wählt selbst
  --scale steam   Faktor der Steam-Oberfläche
  --scale N       fester Faktor (wird auf unterstützte Stufen gerundet)
  --gamescope     In einer eigenen gamescope-Instanz starten (lokale Anzeige im
                  Desktop Mode); ohne Wirkung, wenn bereits eine Gaming-Mode-
                  Sitzung läuft. Steam Link braucht Steam im Gaming Mode
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
- Mit `--gamescope` wird vorher eine eigene gamescope-Instanz gestartet
  (`--backend sdl -f`, unter Wayland mit `SDL_VIDEODRIVER=x11`). Das Fenster
  ist damit im Desktop Mode lokal sichtbar. Für Steam Link wählt Steam darin
  aber ein internes Fenster als Aufnahmequelle, deshalb muss Steam im Gaming
  Mode laufen. Läuft bereits gamescope, entfällt dieser Schritt.
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
`.bak.<Zeitstempel>`. Den Shortcut selbst in Steam entfernen (Rechtsklick →
Verwalten → Von Bibliothek entfernen) oder aus `shortcuts.vdf` löschen; die
Datei dabei nur bei beendetem Steam bearbeiten.

## Lizenzhinweise

Das GNOME-Logo und die GNOME-Schriftmarke sind Marken der GNOME Foundation.
Die mitgelieferten Grafiken sind für die private Nutzung dieses Shortcuts
gedacht. Der Wrapper ist ein lokales Skript ohne Gewähr.
