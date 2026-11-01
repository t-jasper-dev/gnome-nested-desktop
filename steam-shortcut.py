#!/usr/bin/env python3
"""Steam-Non-Steam-Shortcut in shortcuts.vdf anlegen/aktualisieren.

Steam speichert Nicht-Steam-Shortcuts in einer binaeren KeyValues-Datei
(userdata/<ID>/config/shortcuts.vdf). Dieses Skript liest die Datei, haengt
einen Eintrag an bzw. aktualisiert ihn und schreibt sie atomar zurueck.
Bestehende Eintraege bleiben unveraendert.

Aufruf:
    steam-shortcut.py appid DATEI --name NAME --exe PFAD
    steam-shortcut.py add DATEI --name NAME --exe PFAD --startdir DIR \
        --icon PFAD [--launch-options OPTS] [--appid N]
    steam-shortcut.py list DATEI
"""

import argparse
import os
import struct
import sys
import tempfile
import zlib

T_OBJECT = 0x00
T_STRING = 0x01
T_INT32 = 0x02
T_FLOAT32 = 0x03
T_POINTER = 0x04
T_WSTRING = 0x05
T_COLOR = 0x06
T_INT64 = 0x07
T_END = 0x08

APPID_HIGH_BIT = 0x80000000


class VdfError(Exception):
    pass


def _read_cstr(data, pos):
    end = data.find(b"\x00", pos)
    if end < 0:
        raise VdfError("unterminated string")
    return data[pos:end].decode("utf-8", "surrogateescape"), end + 1


def _write_cstr(text):
    return text.encode("utf-8", "surrogateescape") + b"\x00"


def _read_wstring(data, pos):
    end = pos
    while end + 1 < len(data) and data[end:end + 2] != b"\x00\x00":
        end += 2
    if end + 1 >= len(data):
        raise VdfError("unterminated wide string")
    return data[pos:end].decode("utf-16-le", "surrogateescape"), end + 2


def _write_wstring(text):
    return text.encode("utf-16-le", "surrogateescape") + b"\x00\x00"


def _parse_object(data, pos):
    obj = {}
    while True:
        if pos >= len(data):
            raise VdfError("unexpected end of file")
        kind = data[pos]
        pos += 1
        if kind == T_END:
            return obj, pos
        key, pos = _read_cstr(data, pos)
        if kind == T_OBJECT:
            value, pos = _parse_object(data, pos)
        elif kind == T_STRING:
            value, pos = _read_cstr(data, pos)
        elif kind == T_INT32:
            value = struct.unpack_from("<I", data, pos)[0]
            pos += 4
        elif kind == T_FLOAT32:
            value = struct.unpack_from("<f", data, pos)[0]
            pos += 4
        elif kind == T_INT64:
            value = struct.unpack_from("<Q", data, pos)[0]
            pos += 8
        elif kind == T_POINTER:
            value = struct.unpack_from("<I", data, pos)[0]
            pos += 4
        elif kind == T_COLOR:
            value = data[pos:pos + 4]
            pos += 4
        elif kind == T_WSTRING:
            value, pos = _read_wstring(data, pos)
        else:
            raise VdfError("unknown value type 0x%02x for key %r" % (kind, key))
        obj[key] = (kind, value)


def _write_object(obj, out):
    for key, (kind, value) in obj.items():
        out.append(bytes((kind,)))
        out.append(_write_cstr(key))
        if kind == T_OBJECT:
            _write_object(value, out)
        elif kind == T_STRING:
            out.append(_write_cstr(value))
        elif kind == T_INT32:
            out.append(struct.pack("<I", value & 0xFFFFFFFF))
        elif kind == T_FLOAT32:
            out.append(struct.pack("<f", value))
        elif kind == T_INT64:
            out.append(struct.pack("<Q", value & 0xFFFFFFFFFFFFFFFF))
        elif kind == T_POINTER:
            out.append(struct.pack("<I", value & 0xFFFFFFFF))
        elif kind == T_COLOR:
            out.append(bytes(value))
        elif kind == T_WSTRING:
            out.append(_write_wstring(value))
        else:
            raise VdfError("cannot write value type 0x%02x" % kind)
    out.append(bytes((T_END,)))


def load(path):
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return {"shortcuts": (T_OBJECT, {})}
    with open(path, "rb") as handle:
        data = handle.read()
    if not data or data[0] != T_OBJECT:
        raise VdfError("not a binary VDF file")
    key, pos = _read_cstr(data, 1)
    value, pos = _parse_object(data, pos)
    if key != "shortcuts":
        raise VdfError("unexpected root key %r" % key)
    return {key: (T_OBJECT, value)}


def dump(root, path):
    out = [bytes((T_OBJECT,))]
    for key, (kind, value) in root.items():
        out.append(_write_cstr(key))
        if kind == T_OBJECT:
            _write_object(value, out)
        else:
            raise VdfError("root value must be an object")
    # Die Datei endet mit zwei 0x08: eines schließt das "shortcuts"-Objekt
    # (siehe _write_object), das zweite ist der Datei-Terminator.
    out.append(bytes((T_END,)))
    payload = b"".join(out)

    directory = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(directory, exist_ok=True)
    try:
        mode = os.stat(path).st_mode & 0o777
    except OSError:
        mode = 0o600
    fd, tmp = tempfile.mkstemp(prefix=".shortcuts.", dir=directory)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(payload)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        value = value[1:-1]
    return value


def _norm_exe(value):
    value = _unquote(value)
    if not value:
        return ""
    return os.path.normpath(os.path.expanduser(value))


def _quote(path):
    return '"%s"' % path


def _str_field(entry, key, default=""):
    kind, value = entry.get(key, (T_STRING, default))
    return value if kind == T_STRING else default


def compute_appid(exe, name):
    # Steam bildet die ID aus dem gequoteten Exe-Pfad plus dem Namen.
    payload = (_quote(_unquote(exe)) + name).encode("utf-8", "surrogateescape")
    return (zlib.crc32(payload) & 0xFFFFFFFF) | APPID_HIGH_BIT


def find_entry(shortcuts, exe, name):
    wanted_exe = _norm_exe(exe)
    for key, (kind, entry) in shortcuts.items():
        if kind != T_OBJECT:
            continue
        entry_exe = _norm_exe(_str_field(entry, "Exe"))
        entry_name = _str_field(entry, "AppName")
        if wanted_exe and entry_exe and entry_exe == wanted_exe:
            return key, entry
        if entry_name and name and entry_name.casefold() == name.casefold():
            return key, entry
    return None, None


def _entry_appid(entry):
    kind, value = entry.get("appid", (T_INT32, 0))
    return value if kind == T_INT32 else 0


def resolve_appid(root, exe, name, appid=None):
    shortcuts = root["shortcuts"][1]
    _, entry = find_entry(shortcuts, exe, name)
    if entry is not None:
        existing = _entry_appid(entry)
        if appid is None and existing:
            return existing
    if appid is not None:
        return appid
    return compute_appid(exe, name)


def add(root, *, name, exe, startdir, icon, launch_options="", appid=None):
    shortcuts = root["shortcuts"][1]
    key, entry = find_entry(shortcuts, exe, name)
    if entry is None:
        index = 0
        while str(index) in shortcuts:
            index += 1
        key = str(index)
        entry = {}
        shortcuts[key] = (T_OBJECT, entry)

    resolved = resolve_appid(root, exe, name, appid)
    fields = [
        ("appid", T_INT32, resolved),
        ("AppName", T_STRING, name),
        ("Exe", T_STRING, _quote(exe)),
        ("StartDir", T_STRING, _quote(startdir)),
        ("icon", T_STRING, _quote(icon)),
        ("ShortcutPath", T_STRING, ""),
        ("LaunchOptions", T_STRING, launch_options),
        ("IsHidden", T_INT32, 0),
        ("AllowDesktopConfig", T_INT32, 1),
        ("AllowOverlay", T_INT32, 1),
        ("OpenVR", T_INT32, 0),
        ("Devkit", T_INT32, 0),
        ("DevkitGameID", T_STRING, ""),
        ("DevkitOverrideAppID", T_INT32, 0),
        ("LastPlayTime", T_INT32, 0),
        ("FlatpakAppID", T_STRING, ""),
    ]
    for field, kind, value in fields:
        entry[field] = (kind, value)
    if "tags" not in entry:
        entry["tags"] = (T_OBJECT, {})
    return resolved


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p):
        p.add_argument("path", help="Pfad zu shortcuts.vdf")
        p.add_argument("--name", required=True, help="Name des Shortcuts")
        p.add_argument("--exe", required=True, help="Zielprogramm")

    p_appid = sub.add_parser("appid", help="AppID ermitteln (ohne Schreiben)")
    common(p_appid)
    p_appid.add_argument("--appid", type=int)

    p_add = sub.add_parser("add", help="Shortcut anlegen/aktualisieren")
    common(p_add)
    p_add.add_argument("--startdir", required=True)
    p_add.add_argument("--icon", required=True)
    p_add.add_argument("--launch-options", default="")
    p_add.add_argument("--appid", type=int)

    p_list = sub.add_parser("list", help="Vorhandene Shortcuts anzeigen")
    p_list.add_argument("path")

    if argv is None:
        argv = sys.argv[1:]
    else:
        argv = list(argv)

    # Startoptionen beginnen oft selbst mit "--" (z. B. "--gamescope").
    # argparse würde den Wert sonst für eine weitere Option halten.
    normalized = []
    i = 0
    while i < len(argv):
        if argv[i] == "--launch-options" and i + 1 < len(argv):
            normalized.append("--launch-options=" + argv[i + 1])
            i += 2
        else:
            normalized.append(argv[i])
            i += 1

    args = parser.parse_args(normalized)

    try:
        if args.command == "list":
            root = load(args.path)
            for key, (kind, entry) in root["shortcuts"][1].items():
                if kind != T_OBJECT:
                    continue
                print("%s\t%s\t%s" % (
                    _entry_appid(entry),
                    _str_field(entry, "AppName"),
                    _str_field(entry, "Exe"),
                ))
            return 0

        root = load(args.path)
        if args.command == "appid":
            print(resolve_appid(root, args.exe, args.name, args.appid))
            return 0

        appid = add(
            root,
            name=args.name,
            exe=args.exe,
            startdir=args.startdir,
            icon=args.icon,
            launch_options=args.launch_options,
            appid=args.appid,
        )
        dump(root, args.path)
        print(appid)
        return 0
    except (OSError, VdfError) as exc:
        print("steam-shortcut: %s" % exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
