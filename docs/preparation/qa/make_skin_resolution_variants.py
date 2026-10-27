#!/usr/bin/env python3
"""Create #RESOLUTION variants of the LR2 standard skin for UHD-01 tests.

Standard library only. Given --lr2-root (an extracted LR2beta3 folder, never a
path inside this repository), it copies LR2files/Theme/<source> to sibling
folders and inserts a `#RESOLUTION,<n>` line right after the `#INFORMATION`
line of every .lr2skin file:

    LR2_res0      #RESOLUTION,0     -> 640x480   (LR2_skinmanage.cpp:258-261)
    LR2_res1      #RESOLUTION,1     -> 1280x720  (262-265)
    LR2_res2      #RESOLUTION,2     -> 1920x1080 (266-269)
    LR2_res3      #RESOLUTION,3     -> 3840x2160 (270-273)
    LR2_res_bad   #RESOLUTION,abc   -> atol("abc") = 0 -> case 0 (SplitCSV, En_fileutil.cpp:478+)
    LR2_res9      #RESOLUTION,9     -> default branch: targetX = max(9,640), targetY = max(0,480) (274-277)
    LR2_res_before (opt-in) #RESOLUTION,2 placed BEFORE #INFORMATION -> writes Data[Count-1]
                  with Count possibly 0 (TOFIX at LR2_skinmanage.cpp:258). May crash: enable
                  only with --include-before-information.

Only .lr2skin files are copied by default. The LR2 standard skin references its
images and #INCLUDE csv files by root-relative paths (LR2files\\Theme\\LR2\\...),
so the copies keep using the original assets. Pass --full-copy to duplicate the
whole theme folder instead. The #INFORMATION title field gets " [resN]" appended
so each variant is distinguishable in the skin select screen.

The script never modifies the source folder. It writes
<lr2-root>/LR2files/Theme/<source>_res_variants.json describing every change.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

SCRIPT_VERSION = "1.0.0"

VARIANTS = [
    # (folder suffix, resolution value, placement, tag)
    ("res0", "0", "after", "res0"),
    ("res1", "1", "after", "res1"),
    ("res2", "2", "after", "res2"),
    ("res3", "3", "after", "res3"),
    ("res_bad", "abc", "after", "res_bad"),
    ("res9", "9", "after", "res9"),
]
VARIANT_BEFORE = ("res_before", "2", "before", "res_before")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def patch_skin(data: bytes, value: str, placement: str, tag: str) -> tuple[bytes, dict]:
    """Byte-level edit so CP932 text is never re-encoded."""
    lines = data.splitlines(keepends=True)
    info_idx = None
    removed = 0
    kept: list[bytes] = []
    for ln in lines:
        head = ln.lstrip().upper()
        if head.startswith(b"#RESOLUTION"):
            removed += 1
            continue
        if info_idx is None and head.startswith(b"#INFORMATION"):
            info_idx = len(kept)
        kept.append(ln)
    report = {
        "information_found": info_idx is not None,
        "removed_existing_resolution_lines": removed,
        "inserted": None,
        "inserted_at_line": None,
        "title_old": None,
        "title_new": None,
    }
    if info_idx is None:
        return b"".join(kept), report

    info = kept[info_idx]
    eol = b"\r\n" if info.endswith(b"\r\n") else (b"\n" if info.endswith(b"\n") else b"\r\n")
    body = info.rstrip(b"\r\n")
    fields = body.split(b",")
    title_old = fields[2].decode("cp932", errors="replace") if len(fields) > 2 else None
    if len(fields) > 2:
        fields[2] = fields[2] + b" [" + tag.encode("ascii") + b"]"
    kept[info_idx] = b",".join(fields) + eol
    new_line = b"#RESOLUTION," + value.encode("ascii") + eol
    if placement == "after":
        kept.insert(info_idx + 1, new_line)
        report["inserted_at_line"] = info_idx + 2  # 1-based
    else:
        kept.insert(info_idx, new_line)
        report["inserted_at_line"] = info_idx + 1
    report["inserted"] = new_line.decode("ascii").rstrip()
    report["title_old"] = title_old
    report["title_new"] = fields[2].decode("cp932", errors="replace") if len(fields) > 2 else None
    return b"".join(kept), report


def make_variant(src: Path, dst: Path, value: str, placement: str, tag: str, full_copy: bool) -> list[dict]:
    if full_copy:
        shutil.copytree(src, dst)
    else:
        dst.mkdir(parents=True)
    changes = []
    for skin in sorted(src.rglob("*")):
        if not skin.is_file() or skin.suffix.lower() not in (".lr2skin", ".lr2ss"):
            continue
        rel = skin.relative_to(src)
        target = dst / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        original = skin.read_bytes()
        patched, report = patch_skin(original, value, placement, tag)
        target.write_bytes(patched)
        changes.append({
            "source": skin.as_posix(),
            "target": target.as_posix(),
            "source_sha256": sha256(original),
            "target_sha256": sha256(patched),
            **report,
        })
    return changes


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lr2-root", type=Path, required=True, help="extracted LR2beta3 folder (contains LR2files/)")
    ap.add_argument("--source-theme", default="LR2", help="theme folder name under LR2files/Theme (default: LR2)")
    ap.add_argument("--full-copy", action="store_true", help="copy the whole theme folder, not only .lr2skin files")
    ap.add_argument("--include-before-information", action="store_true",
                    help="also create <theme>_res_before with #RESOLUTION placed before #INFORMATION (may crash LR2)")
    ap.add_argument("--force", action="store_true", help="remove existing variant folders first")
    args = ap.parse_args(argv)

    root: Path = args.lr2_root.resolve()
    repo_marker = Path(__file__).resolve().parents[3]
    try:
        root.relative_to(repo_marker)
        print(f"error: --lr2-root must not be inside the repository ({repo_marker})", file=sys.stderr)
        return 2
    except ValueError:
        pass
    theme_dir = root / "LR2files" / "Theme"
    src = theme_dir / args.source_theme
    if not src.is_dir():
        print(f"error: source theme folder not found: {src}", file=sys.stderr)
        return 2
    if not any(p.suffix.lower() == ".lr2skin" for p in src.rglob("*")):
        print(f"error: no .lr2skin files under {src}", file=sys.stderr)
        return 2

    variants = list(VARIANTS)
    if args.include_before_information:
        variants.append(VARIANT_BEFORE)

    targets = [theme_dir / f"{args.source_theme}_{suffix}" for suffix, *_ in variants]
    existing = [t for t in targets if t.exists()]
    if existing:
        if not args.force:
            print("error: variant folders already exist (use --force): " + ", ".join(str(t) for t in existing),
                  file=sys.stderr)
            return 2
        for t in existing:
            shutil.rmtree(t)

    result = {
        "script": "make_skin_resolution_variants.py",
        "script_version": SCRIPT_VERSION,
        "source_theme": src.as_posix(),
        "full_copy": args.full_copy,
        "variants": [],
    }
    for (suffix, value, placement, tag), dst in zip(variants, targets):
        changes = make_variant(src, dst, value, placement, tag, args.full_copy)
        result["variants"].append({
            "folder": dst.as_posix(),
            "resolution_value": value,
            "placement": placement,
            "skin_files": len(changes),
            "skins_without_information": sum(1 for c in changes if not c["information_found"]),
            "changes": changes,
        })
        print("%-14s #RESOLUTION,%-4s %-6s %3d skin files -> %s" % (
            dst.name, value, placement, len(changes), dst))

    out_json = theme_dir / f"{args.source_theme}_res_variants.json"
    out_json.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"variants.json: {out_json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
