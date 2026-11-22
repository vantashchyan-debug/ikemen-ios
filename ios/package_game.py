#!/usr/bin/env python3
"""Put an Ikemen GO game (chars, stages, sound, screenpack...) into the iOS app.

Two modes:
  * --app Payload/Ikemen.app --game DIR          (used by build_ios.sh on macOS)
  * --ipa engine.ipa --game DIR --out game.ipa   (works on Linux/Windows, no Mac)

Only the folders the engine reads are copied. save/config.ini is copied with
iPhone-friendly video/sound settings; it seeds Documents/Ikemen/save on first
launch and is never overwritten afterwards.
"""
import argparse
import concurrent.futures
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

ASSET_DIRS = ["data", "external", "font", "chars", "stages", "sound", "video"]
SAVE_FILES = ["config.ini", "stats.json", "touch_layout.json"]
SKIP_NAMES = {".DS_Store", "Thumbs.db", "__pycache__", "desktop.ini"}
SKIP_SUFFIXES = (".orig", ".bak", ".pyc", ".tmp")

# section -> {key: value}
IOS_OVERRIDES = {
    "Video": {
        "RenderMode": "Vulkan 1.3",
        "Fullscreen": "1",
        "Borderless": "0",
        "WindowWidth": "0",
        "WindowHeight": "0",
        "VSync": "1",
        "Framerate": "60",
        "EnableModelShadow": "0",
        "GameWidth": "1280",
        "GameHeight": "720",
        "RendererDebugMode": "0",
    },
    "Sound": {
        "BGMRAMBuffer": "0",
    },
}


def patch_config(text: str) -> str:
    section = None
    out = []
    for line in text.splitlines(keepends=True):
        m = re.match(r"\s*\[([^\]]+)\]", line)
        if m:
            section = m.group(1).strip()
        elif section in IOS_OVERRIDES:
            km = re.match(r"(\s*)([A-Za-z0-9_.]+)(\s*=\s*)([^\r\n]*)(\r?\n?)$", line)
            if km and km.group(2) in IOS_OVERRIDES[section]:
                key = km.group(2)
                val = IOS_OVERRIDES[section][key]
                line = f"{km.group(1)}{key}{km.group(3)}{val}{km.group(5)}"
        out.append(line)
    text = "".join(out)
    # Cap MSAA at 4x (A14 resolves on-tile; more is wasted at 460 ppi)
    text = re.sub(r"(?m)^(\s*MSAA\s*=\s*)(\d+)", lambda m: m.group(1) + str(min(int(m.group(2)), 4)), text)
    return text


def ignore(_dir, names):
    return [n for n in names if n in SKIP_NAMES or n.endswith(SKIP_SUFFIXES)]


def du(path):
    total = 0
    for root, _dirs, files in os.walk(path):
        for f in files:
            fp = os.path.join(root, f)
            if not os.path.islink(fp):
                total += os.path.getsize(fp)
    return total


TEXT_SUFFIXES = (".def", ".lua", ".zss", ".cns", ".st", ".cmd", ".txt", ".ini", ".json")


def compress_music(dest: str, quality: int):
    """FLAC -> Ogg Vorbis inside the app copy only (the game folder on disk is untouched).
    The engine decodes .ogg natively. The sample rate is kept, so bgmloopstart/bgmloopend (in samples) stay valid.
    Every text file that names a .flac is rewritten to the .ogg name."""
    flacs = []
    for root, _dirs, files in os.walk(dest):
        flacs += [os.path.join(root, f) for f in files if f.lower().endswith(".flac")]
    if not flacs:
        return
    before = sum(os.path.getsize(f) for f in flacs)

    def enc(src):
        out = src[: -len(".flac")] + ".ogg"
        r = subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-map", "0:a:0", "-c:a", "libvorbis", "-q:a", str(quality),
                            "-map_metadata", "-1", out], capture_output=True, text=True)
        if r.returncode != 0 or not os.path.exists(out):
            return src, r.stderr.strip() or "ffmpeg failed"
        os.unlink(src)
        return src, None

    with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
        failed = [(s_, e) for s_, e in pool.map(enc, flacs) if e]
    if failed:
        sys.exit("music conversion failed:\n" + "\n".join(f"  {s_}: {e}" for s_, e in failed))
    after = sum(os.path.getsize(f[: -len(".flac")] + ".ogg") for f in flacs)
    pat = re.compile(r"(?i)\.flac\b")
    fixed = 0
    for root, _dirs, files in os.walk(dest):
        for f in files:
            if not f.lower().endswith(TEXT_SUFFIXES):
                continue
            fp = os.path.join(root, f)
            with open(fp, encoding="utf-8", errors="surrogateescape") as fh:
                text = fh.read()
            if pat.search(text):
                with open(fp, "w", encoding="utf-8", errors="surrogateescape") as fh:
                    fh.write(pat.sub(".ogg", text))
                fixed += 1
    print(f"  ~ music: {len(flacs)} FLAC -> Ogg Vorbis q{quality}: {before / 1e6:.1f} MB -> {after / 1e6:.1f} MB "
          f"({fixed} files re-pointed)")


def install_game(app: str, game: str, music_quality: int = 4):
    if not os.path.isfile(os.path.join(game, "save", "config.ini")) and not os.path.isdir(os.path.join(game, "data")):
        sys.exit(f"'{game}' does not look like an Ikemen GO folder (no data/ or save/config.ini)")
    dest = os.path.join(app, "game")
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(os.path.join(dest, "save"))
    for d in ASSET_DIRS:
        src = os.path.join(game, d)
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(dest, d), ignore=ignore, symlinks=False)
            print(f"  + {d:9s} {du(os.path.join(dest, d)) / 1e6:8.1f} MB")
        else:
            print(f"  - {d:9s} (not found, skipped)")
    for f in SAVE_FILES:
        src = os.path.join(game, "save", f)
        if not os.path.isfile(src):
            continue
        if f == "config.ini":
            with open(src, encoding="utf-8-sig", errors="surrogateescape") as fh:
                text = fh.read()
            with open(os.path.join(dest, "save", f), "w", encoding="utf-8", errors="surrogateescape") as fh:
                fh.write(patch_config(text))
            print("  + save/config.ini (iOS video/sound settings applied)")
        else:
            shutil.copy2(src, os.path.join(dest, "save", f))
            print(f"  + save/{f}")
    if music_quality >= 0:
        compress_music(dest, music_quality)
    print(f"  game total: {du(dest) / 1e6:.1f} MB")


def extract_ipa(ipa: str, into: str) -> str:
    with zipfile.ZipFile(ipa) as z:
        for info in z.infolist():
            path = z.extract(info, into)
            mode = (info.external_attr >> 16) & 0o777
            if mode and not info.is_dir():
                os.chmod(path, mode)
    apps = [d for d in os.listdir(os.path.join(into, "Payload")) if d.endswith(".app")]
    if not apps:
        sys.exit("no Payload/*.app inside the .ipa")
    app = os.path.join(into, "Payload", apps[0])
    exe = os.path.join(app, "Ikemen")
    if os.path.exists(exe):
        os.chmod(exe, os.stat(exe).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return app


def write_ipa(root: str, out: str):
    tmp = out + ".part"
    stored = (".png", ".flac", ".ogg", ".mp3", ".webm", ".jpg", ".zip", ".sff", ".snd")
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for base, dirs, files in os.walk(os.path.join(root, "Payload")):
            dirs.sort()
            rel_dir = os.path.relpath(base, root)
            zi = zipfile.ZipInfo(rel_dir.replace(os.sep, "/") + "/")
            zi.external_attr = (0o40755 << 16) | 0x10
            z.writestr(zi, b"")
            for f in sorted(files):
                fp = os.path.join(base, f)
                arc = os.path.relpath(fp, root).replace(os.sep, "/")
                comp = zipfile.ZIP_STORED if f.lower().endswith(stored) else zipfile.ZIP_DEFLATED
                z.write(fp, arc, compress_type=comp)
    os.replace(tmp, out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game", required=True, help="Ikemen GO game folder (contains data/, chars/, save/...)")
    ap.add_argument("--app", help="Ikemen.app directory to modify in place")
    ap.add_argument("--ipa", help="engine .ipa built by CI")
    ap.add_argument("--out", help="output .ipa (with --ipa)")
    ap.add_argument("--music-quality", type=int, default=4,
                    help="Ogg Vorbis quality for the music (0..10, default 4 ~ 128 kbps); -1 keeps the original FLAC")
    a = ap.parse_args()
    game = os.path.abspath(a.game)
    if a.app:
        install_game(a.app, game, a.music_quality)
        return
    if not (a.ipa and a.out):
        ap.error("use --app, or --ipa together with --out")
    with tempfile.TemporaryDirectory() as tmp:
        print(f"Extracting {a.ipa}")
        app = extract_ipa(a.ipa, tmp)
        print(f"Adding game from {game}")
        install_game(app, game, a.music_quality)
        print(f"Writing {a.out}")
        write_ipa(tmp, a.out)
    print(f"Done: {a.out} ({os.path.getsize(a.out) / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
