#!/usr/bin/env python3
"""MVP-3 (app-store-compliance.md R14, ASC-12; ux-ui.md UX-WP-23): the App Store screenshot
pipeline's post-processing. `StoreScreenshotUITests` (apps/TallyiOS/TallyUITests) captures 8
scenes on the Pro Max simulator, one leg per appearance x language (light/dark x en/es), each
attachment named `NN-<scene>.png`. This script turns those raw legs into what the brief asks for:

- flattened to RGB (no alpha);
- asserted at exactly 1320x2868 (R14's iPhone 6.9" size, which satisfies the 6.5" requirement);
- renamed `NN-<scene>-<light|dark>-<en|es>.png`;
- a manifest (scene, size, mode, language, SHA-256) that `check_release.py --screenshots` turns
  into `REL.store.screenshots`.

**Nothing synthetic.** Every output pixel comes from the raw capture; the only change is
flattening (an alpha channel, if any, is composited onto white). No marketing captions, no
recompositing that changes app content.

    python3 scripts/release/screenshots.py --raw RAWDIR --out OUTDIR
        RAWDIR holds one subdirectory per leg, named store-shots-<light|dark>-<en|es> (the
        workflow's own per-leg artifact name), each with the 8 raw NN-<scene>.png captures. Writes
        the final named PNGs plus manifest.json to OUTDIR. A raw image that is missing, unreadable,
        or not exactly 1320x2868 after flattening is recorded in the manifest's "errors" and left
        out of "images" -- nothing passes by being missing.
    python3 scripts/release/screenshots.py --contact-sheets FINALDIR --out OUTDIR
        One owner-sheet-<language>.jpg per language found in FINALDIR's file names: a portrait
        grid, light and dark side by side per scene, under 4000 px tall (split into -1/-2/... if
        needed) and under 1.5 MB.
    python3 scripts/release/screenshots.py --self-test

Exit codes: 0 when every expected image passed; 1 when the manifest has any missing scene/leg or
any image that failed its own checks (still written, so the report shows what is wrong); 2 on a
usage or input error (Pillow not installed, RAWDIR unreadable, ...).
"""
from __future__ import annotations

import hashlib
import io
import json
import pathlib
import re
import sys

SCENES: tuple[tuple[int, str], ...] = (
    (1, "dashboard"), (2, "courses"), (3, "course-detail"), (4, "what-if"),
    (5, "todo"), (6, "calendar"), (7, "insights"), (8, "quiet-hours"),
)
MODES = ("light", "dark")
LANGUAGES = ("en", "es")
REQUIRED_SIZE = (1320, 2868)
LEG_DIR_RE = re.compile(r"^store-shots-(light|dark)-(en|es)$")
FINAL_FILE_RE = re.compile(r"^(\d{2})-([a-z-]+)-(light|dark)-(en|es)\.png$")

MAX_CONTACT_SHEET_HEIGHT = 4000
MAX_CONTACT_SHEET_BYTES = 1_500_000


class InputError(Exception):
    pass


def _pillow():
    try:
        from PIL import Image
    except ImportError as error:
        raise InputError("Pillow is required for this script (pip install --user pillow)") from error
    return Image


def _has_alpha(image) -> bool:
    return image.mode in ("RGBA", "LA") or (image.mode == "P" and "transparency" in image.info)


def flatten_to_rgb(image):
    """`image`, flattened to plain RGB. An alpha channel (if any) is composited onto white -- the
    only change this makes; everything else is a straight mode conversion. Never redraws or
    recolours app content."""
    if _has_alpha(image):
        Image = _pillow()
        rgba = image.convert("RGBA")
        background = Image.new("RGB", rgba.size, (255, 255, 255))
        background.paste(rgba, mask=rgba.split()[-1])
        return background
    return image.convert("RGB")


def process_raw(raw_dir: pathlib.Path, out_dir: pathlib.Path) -> dict:
    """Walks `raw_dir`'s `store-shots-<mode>-<language>` subdirectories, flattens and validates
    each of the 8 expected scenes, writes the ones that pass to `out_dir` named
    `NN-<scene>-<mode>-<language>.png`, and returns the manifest dict. A bad image is recorded in
    `errors` and left out of `images` rather than raising -- the same "nothing passes by being
    missing" rule `check_release.py`'s own checks use."""
    Image = _pillow()
    out_dir.mkdir(parents=True, exist_ok=True)
    images: list[dict] = []
    errors: list[str] = []
    legs_found: set[tuple[str, str]] = set()

    leg_dirs = sorted(p for p in raw_dir.iterdir() if p.is_dir()) if raw_dir.is_dir() else []
    for leg_dir in leg_dirs:
        match = LEG_DIR_RE.match(leg_dir.name)
        if not match:
            continue
        mode, language = match.group(1), match.group(2)
        legs_found.add((mode, language))
        for number, scene in SCENES:
            raw_name = f"{number:02d}-{scene}.png"
            raw_path = leg_dir / raw_name
            if not raw_path.exists():
                errors.append(f"{leg_dir.name}/{raw_name}: missing from the raw capture")
                continue
            try:
                with Image.open(raw_path) as opened:
                    opened.load()
                    had_alpha = _has_alpha(opened)
                    flattened = flatten_to_rgb(opened)
            except Exception as error:  # noqa: BLE001 - an unreadable capture is reported, not fatal
                errors.append(f"{leg_dir.name}/{raw_name}: unreadable ({error})")
                continue
            if flattened.size != REQUIRED_SIZE:
                errors.append(f"{leg_dir.name}/{raw_name}: {flattened.size[0]}x{flattened.size[1]}, "
                              f"expected {REQUIRED_SIZE[0]}x{REQUIRED_SIZE[1]}")
                continue
            out_name = f"{number:02d}-{scene}-{mode}-{language}.png"
            out_path = out_dir / out_name
            flattened.save(out_path, format="PNG")
            sha256 = hashlib.sha256(out_path.read_bytes()).hexdigest()
            images.append({
                "file": out_name, "scene": scene, "number": number, "mode": mode, "language": language,
                "width": flattened.size[0], "height": flattened.size[1], "sha256": sha256, "hadAlpha": had_alpha,
            })

    expected = {(scene, mode, language) for _, scene in SCENES for mode in MODES for language in LANGUAGES}
    found = {(img["scene"], img["mode"], img["language"]) for img in images}
    missing = sorted(f"{scene}-{mode}-{language}" for scene, mode, language in expected - found)
    missing_legs = sorted(f"{mode}-{language}" for mode in MODES for language in LANGUAGES
                          if (mode, language) not in legs_found)

    manifest = {
        "scenes": [name for _, name in SCENES], "modes": list(MODES), "languages": list(LANGUAGES),
        "requiredSize": {"width": REQUIRED_SIZE[0], "height": REQUIRED_SIZE[1]},
        "images": sorted(images, key=lambda i: (i["number"], i["mode"], i["language"])),
        "missing": missing, "missingLegs": missing_legs, "errors": errors,
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest


def build_contact_sheets(final_dir: pathlib.Path, out_dir: pathlib.Path,
                         max_height: int = MAX_CONTACT_SHEET_HEIGHT, max_bytes: int = MAX_CONTACT_SHEET_BYTES) -> list[pathlib.Path]:
    """One contact sheet per language found in `final_dir`'s `NN-<scene>-<mode>-<language>.png`
    file names: a portrait grid, light and dark thumbnails side by side per scene, each row
    labelled with the scene's number and name. Split across `-1`, `-2`, ... parts so each stays
    under `max_height` px tall; each part's JPEG quality steps down until it is under `max_bytes`."""
    Image = _pillow()
    from PIL import ImageDraw, ImageFont

    by_language: dict[str, dict[str, dict[str, pathlib.Path]]] = {}
    for path in sorted(final_dir.glob("*.png")):
        match = FINAL_FILE_RE.match(path.name)
        if not match:
            continue
        number, scene, mode, language = match.groups()
        key = f"{number}-{scene}"
        by_language.setdefault(language, {}).setdefault(key, {})[mode] = path

    thumb_width = 300
    label_height = 28
    column_gap = 15
    out_dir.mkdir(parents=True, exist_ok=True)
    written: list[pathlib.Path] = []

    for language, scenes in sorted(by_language.items()):
        rows: list[tuple[str, dict[str, "Image.Image"]]] = []
        for key in sorted(scenes):
            cells: dict[str, "Image.Image"] = {}
            for mode in MODES:
                path = scenes[key].get(mode)
                if not path:
                    continue
                with Image.open(path) as opened:
                    ratio = thumb_width / opened.width
                    cells[mode] = opened.convert("RGB").resize((thumb_width, round(opened.height * ratio)))
            rows.append((key, cells))
        if not rows:
            continue

        row_height = max((img.height for cells in (r[1] for r in rows) for img in cells.values()), default=0) + label_height
        sheet_width = thumb_width * len(MODES) + column_gap * (len(MODES) - 1) + 16

        parts: list[list[tuple[str, dict[str, "Image.Image"]]]] = []
        current: list[tuple[str, dict[str, "Image.Image"]]] = []
        current_height = 0
        for row in rows:
            if current and current_height + row_height > max_height:
                parts.append(current)
                current, current_height = [], 0
            current.append(row)
            current_height += row_height
        if current:
            parts.append(current)

        font = ImageFont.load_default()
        for index, part in enumerate(parts, start=1):
            sheet = Image.new("RGB", (sheet_width, len(part) * row_height), (245, 245, 245))
            draw = ImageDraw.Draw(sheet)
            for row_index, (key, cells) in enumerate(part):
                y = row_index * row_height
                draw.text((8, y + 4), key, fill=(20, 20, 20), font=font)
                for column, mode in enumerate(MODES):
                    cell = cells.get(mode)
                    if cell:
                        sheet.paste(cell, (column * (thumb_width + column_gap) + 8, y + label_height))
            suffix = "" if len(parts) == 1 else f"-{index}"
            out_path = out_dir / f"owner-sheet-{language}{suffix}.jpg"
            quality = 85
            while True:
                buffer = io.BytesIO()
                sheet.save(buffer, format="JPEG", quality=quality)
                if buffer.tell() <= max_bytes or quality <= 40:
                    out_path.write_bytes(buffer.getvalue())
                    break
                quality -= 10
            written.append(out_path)
    return written


# --------------------------------------------------------------------------------------------
# Self-test
# --------------------------------------------------------------------------------------------

def self_test() -> int:
    import shutil
    import tempfile

    Image = _pillow()
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="screenshots-selftest-"))
    try:
        # flatten_to_rgb: an RGBA image with partial transparency becomes plain RGB, same size,
        # content otherwise unchanged (an opaque pixel keeps its colour exactly).
        rgba = Image.new("RGBA", (4, 4), (10, 20, 30, 255))
        rgba.putpixel((0, 0), (10, 20, 30, 0))  # fully transparent corner -> composites to white
        flattened = flatten_to_rgb(rgba)
        assert flattened.mode == "RGB", flattened.mode
        assert flattened.size == (4, 4)
        assert flattened.getpixel((1, 1)) == (10, 20, 30), flattened.getpixel((1, 1))
        assert flattened.getpixel((0, 0)) == (255, 255, 255), flattened.getpixel((0, 0))
        # An already-opaque RGB image passes through unchanged.
        opaque = Image.new("RGB", (4, 4), (1, 2, 3))
        assert flatten_to_rgb(opaque).tobytes() == opaque.tobytes()

        # process_raw: one complete leg (all 8 scenes, right size) plus one leg missing a scene
        # and one leg with a wrong-sized image -- every outcome must show up, nothing silently
        # dropped.
        raw = tmp / "raw"
        light_en = raw / "store-shots-light-en"
        light_en.mkdir(parents=True)
        for number, scene in SCENES:
            Image.new("RGBA", REQUIRED_SIZE, (5, 5, 5, 255)).save(light_en / f"{number:02d}-{scene}.png")

        dark_en = raw / "store-shots-dark-en"
        dark_en.mkdir(parents=True)
        for number, scene in SCENES:
            if scene == "todo":
                continue  # missing on purpose
            Image.new("RGB", REQUIRED_SIZE, (6, 6, 6)).save(dark_en / f"{number:02d}-{scene}.png")

        light_es = raw / "store-shots-light-es"
        light_es.mkdir(parents=True)
        for number, scene in SCENES:
            size = (100, 100) if scene == "calendar" else REQUIRED_SIZE
            Image.new("RGB", size, (7, 7, 7)).save(light_es / f"{number:02d}-{scene}.png")
        # store-shots-dark-es is entirely absent -> a missing leg.

        out = tmp / "final"
        manifest = process_raw(raw, out)
        assert len(manifest["images"]) == 8 + 7 + 7, len(manifest["images"])  # light-en 8, dark-en 7, light-es 7
        assert "todo-dark-en" in manifest["missing"], manifest["missing"]
        assert "calendar-light-es" in manifest["missing"], manifest["missing"]
        assert "dark-es" in manifest["missingLegs"], manifest["missingLegs"]
        assert any("calendar" in e and "100x100" in e for e in manifest["errors"]), manifest["errors"]
        assert any("todo" in e and "missing" in e for e in manifest["errors"]), manifest["errors"]
        light_en_image = next(i for i in manifest["images"] if i["scene"] == "dashboard" and i["mode"] == "light"
                              and i["language"] == "en")
        assert light_en_image["hadAlpha"] is True, light_en_image
        assert light_en_image["width"] == REQUIRED_SIZE[0] and light_en_image["height"] == REQUIRED_SIZE[1]
        on_disk = out / "01-dashboard-light-en.png"
        assert on_disk.exists()
        assert light_en_image["sha256"] == hashlib.sha256(on_disk.read_bytes()).hexdigest()
        with Image.open(on_disk) as written:
            assert written.mode == "RGB", "output must have no alpha"
        manifest_on_disk = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
        assert manifest_on_disk == manifest

        # An empty raw directory: every combination missing, nothing crashes.
        empty_out = tmp / "empty-final"
        empty_manifest = process_raw(tmp / "does-not-exist", empty_out)
        assert empty_manifest["images"] == []
        assert len(empty_manifest["missing"]) == len(SCENES) * len(MODES) * len(LANGUAGES)
        assert set(empty_manifest["missingLegs"]) == {f"{m}-{l}" for m in MODES for l in LANGUAGES}

        # build_contact_sheets: one sheet per language present, under the byte cap, under the
        # height cap (a cap narrow enough to hold only 2 of the 8 scene rows proves the splitting
        # logic actually splits, without demanding a cap smaller than a single row -- each
        # thumbnail alone is ~680 px tall at this script's own 300 px thumbnail width).
        sheets_out = tmp / "sheets"
        tight_cap = 1500
        sheets = build_contact_sheets(out, sheets_out, max_height=tight_cap, max_bytes=MAX_CONTACT_SHEET_BYTES)
        assert sheets, "no contact sheets were written"
        languages_seen = {p.stem.split("-")[2] for p in sheets}
        assert languages_seen == {"en", "es"}, languages_seen
        en_parts = [p for p in sheets if "-en" in p.stem]
        assert len(en_parts) > 1, "a tight height cap on 8 scenes must split into more than one part"
        for path in sheets:
            assert path.stat().st_size <= MAX_CONTACT_SHEET_BYTES, (path, path.stat().st_size)
            with Image.open(path) as sheet_image:
                assert sheet_image.height <= tight_cap, (path, sheet_image.height)

        # A byte cap tight enough to force quality all the way down still writes something
        # (the loop's floor at quality 40), never hangs or raises.
        tiny_cap_sheets = build_contact_sheets(out, tmp / "tiny-sheets", max_height=MAX_CONTACT_SHEET_HEIGHT, max_bytes=500)
        assert all(p.exists() for p in tiny_cap_sheets)

        print("screenshots.py self-test: 1 (flatten) + 2 (process_raw) + 2 (contact sheets) groups passed")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# --------------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------------

def main(argv: list[str]) -> int:
    args = argv[1:]
    try:
        if args == ["--self-test"]:
            return self_test()
        options: dict[str, str] = {}
        key = None
        for arg in args:
            if arg.startswith("--"):
                key = arg
                options[key] = ""
            elif key:
                options[key] = arg
        if "--raw" in options and "--out" in options:
            manifest = process_raw(pathlib.Path(options["--raw"]), pathlib.Path(options["--out"]))
            print(f"SCREENSHOTS | {len(manifest['images'])} image(s) written; "
                  f"{len(manifest['missing'])} missing; {len(manifest['errors'])} error(s)")
            for error in manifest["errors"]:
                print(f"SCREENSHOTS | error | {error}")
            return 0 if not manifest["missing"] and not manifest["errors"] else 1
        if "--contact-sheets" in options and "--out" in options:
            written = build_contact_sheets(pathlib.Path(options["--contact-sheets"]), pathlib.Path(options["--out"]))
            for path in written:
                print(f"SCREENSHOTS | contact sheet | {path} ({path.stat().st_size} bytes)")
            return 0 if written else 1
    except (InputError, OSError, json.JSONDecodeError) as error:
        print(f"SCREENSHOTS | ERROR | {error}")
        return 2
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
