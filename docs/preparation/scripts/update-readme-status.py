#!/usr/bin/env python3
"""Rewrite the fork-status block in README.md from GitHub Project "OpenLR2 Modernization".

Only the text between the two markers below is replaced. Requires `gh` logged in with the
`project` (or `read:project`) scope.

    python3 docs/preparation/scripts/update-readme-status.py [--dry-run]
"""
import datetime
import json
import pathlib
import subprocess
import sys
import urllib.parse

OWNER = "OE-Park"
NUMBER = "2"
BOARD_URL = f"https://github.com/users/{OWNER}/projects/{NUMBER}"
START = "<!-- fork-status:start -->"
END = "<!-- fork-status:end -->"
README = pathlib.Path(__file__).resolve().parents[3] / "README.md"
STATUS_ORDER = ["In Progress", "Todo", "Done"]


def load_items():
    out = subprocess.run(
        ["gh", "project", "item-list", NUMBER, "--owner", OWNER, "--limit", "500", "--format", "json"],
        check=True, capture_output=True, text=True,
    ).stdout
    return json.loads(out)["items"]


def filtered_url(status):
    query = urllib.parse.quote_plus(f'status:"{status}"')
    return f"{BOARD_URL}/views/1?filterQuery={query}"


def render(items):
    today = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).date().isoformat()
    counts = {s: sum(1 for i in items if i.get("status") == s) for s in STATUS_ORDER}
    active = sorted((i for i in items if i.get("status") == "In Progress"),
                    key=lambda i: (i.get("phase", ""), i.get("task ID", "")))
    lines = [
        START,
        "## Fork status (OE-Park/OpenLR2-modernization)",
        "",
        "- EN: Modernization work on this fork: Windows 11 x64 baseline, memory leaks, 4K, macOS arm64, Windows ARM64 (lowest priority).",
        "- KO: 이 포크의 현대화 작업: Windows 11 x64 기준 확보, 메모리 누수, 4K, macOS arm64, Windows ARM64(최후순위).",
        "- JA: このフォークのモダナイズ作業: Windows 11 x64 の基準確保、メモリリーク、4K、macOS arm64、Windows ARM64(最後の優先度)。",
        "",
        f"Board: [OpenLR2 Modernization]({BOARD_URL}) · "
        + " · ".join(f"[{s} ({counts[s]})]({filtered_url(s)})" for s in STATUS_ORDER),
        "",
        "In progress:",
        "",
        "| Task | Phase | Platform | Title |",
        "|---|---|---|---|",
    ]
    for i in active:
        title = i.get("title", "").split("] ", 1)[-1]
        lines.append(f"| {i.get('task ID', '')} | {i.get('phase', '')} | {i.get('platform', '')} | {title} |")
    if not active:
        lines.append("| — | — | — | (none) |")
    lines += [
        "",
        f"<sub>Generated {today} (KST) from the project board by `docs/preparation/scripts/update-readme-status.py`. "
        "Details per card are in Korean, Japanese and English.</sub>",
        END,
    ]
    return "\n".join(lines)


def main():
    text = README.read_text(encoding="utf-8")
    if text.count(START) != 1 or text.count(END) != 1:
        sys.exit(f"README.md must contain exactly one {START} / {END} pair")
    head, rest = text.split(START, 1)
    _, tail = rest.split(END, 1)
    block = render(load_items())
    if "--dry-run" in sys.argv:
        print(block)
        return
    README.write_text(head + block + tail, encoding="utf-8")
    print(f"updated {README}")


if __name__ == "__main__":
    main()
