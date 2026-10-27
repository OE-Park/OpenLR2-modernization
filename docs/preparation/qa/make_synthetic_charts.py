#!/usr/bin/env python3
"""QA-01 synthetic chart generator for OpenLR2 / LR2 comparison runs.

Standard library only. Writes keysound WAVs, BGA BMPs and BMS/BME/PMS charts
into an output folder that is outside the git-tracked tree (default:
<repo>/.local/qa/synthetic, which is gitignored). The output root itself is the
song root to register in LR2: it directly contains the song folders
ascii_basic/, "日本語 曲名 テスト"/, "한국어 곡 테스트"/, case_mismatch/, broken/
and manifest.json. Output is deterministic for a
given --seed: no timestamps are written into any file, and manifest.json lists
every file with its SHA-256.

Format decisions are derived from LR2/LR2_bmsload.cpp, LR2/LR2_songmanage.cpp
and LR2/En_fileutil.cpp of this repository. See docs/preparation/qa/README.md
for the line citations behind each decision.

Usage:
    python3 docs/preparation/qa/make_synthetic_charts.py [--out DIR] [--seed N] [--force]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import shutil
import struct
import sys
import wave
from pathlib import Path

GENERATOR_VERSION = "1.1.0"
DEFAULT_SEED = 1

# Base-62 digit order used by Base62ToInt() in LR2/En_fileutil.cpp:537-549:
# '0'-'9' -> 0-9, 'A'-'Z' -> 10-35, 'a'-'z' -> 36-61. Base36ToInt() (552-565)
# folds 'a'-'z' onto 10-35, so only first-char '0' with second-char [0-9A-Z]
# decodes identically under both bases.
DIGITS62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

KEY_RATE = 44100
KEY_MS = 120
KEY_FADE_MS = 5
BGM_RATE = 22050  # intentionally different from keysounds: exercises resampling
BGM_SECONDS = 8
MUON_MS = 100

CRLF = "\r\n"

# song folders created under the output root (also the only things --force removes)
FOLDER_ASCII = "ascii_basic"
FOLDER_JA = "日本語 曲名 テスト"
FOLDER_KO = "한국어 곡 테스트"
FOLDER_CASE = "case_mismatch"
FOLDER_BROKEN = "broken"
SONG_FOLDERS = (FOLDER_ASCII, FOLDER_JA, FOLDER_KO, FOLDER_CASE, FOLDER_BROKEN)

# ---------------------------------------------------------------------------
# small encoders
# ---------------------------------------------------------------------------


def idx(n: int, base: int = 36) -> str:
    """Two-character object index in base 36 or base 62."""
    if not 0 <= n < base * base:
        raise ValueError(f"index {n} out of range for base {base}")
    return DIGITS62[n // base] + DIGITS62[n % base]


def tone_samples(freq: float, ms: int, rate: int, amp: float, fade_ms: int) -> bytes:
    n = rate * ms // 1000
    fade = max(1, rate * fade_ms // 1000)
    out = []
    for i in range(n):
        env = min(1.0, i / fade, (n - 1 - i) / fade)
        v = amp * env * math.sin(2.0 * math.pi * freq * i / rate)
        out.append(int(round(v * 32767)))
    return struct.pack("<%dh" % n, *out)


def write_wav(path: Path, frames: bytes, rate: int) -> None:
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(frames)


def write_tone(path: Path, freq: float) -> None:
    write_wav(path, tone_samples(freq, KEY_MS, KEY_RATE, 0.5, KEY_FADE_MS), KEY_RATE)


def write_silence(path: Path, ms: int = MUON_MS) -> None:
    n = KEY_RATE * ms // 1000
    write_wav(path, b"\x00\x00" * n, KEY_RATE)


def write_bgm(path: Path, rng: random.Random) -> None:
    """8 s of low 8th-note pulses at 120 BPM (0.25 s each) so BGM/keysound sync is audible."""
    step_ms = 250
    steps = BGM_SECONDS * 1000 // step_ms
    pitches = [110.0, 123.47, 130.81, 146.83]  # A2 B2 C3 D3
    seq = [rng.choice(pitches) for _ in range(steps)]
    body = b"".join(tone_samples(f, step_ms, BGM_RATE, 0.25, 10) for f in seq)
    write_wav(path, body, BGM_RATE)


def write_bmp(path: Path, w: int, h: int, fill, border, inner=None) -> None:
    """24-bit BI_RGB bottom-up BMP. inner=(x0,y0,x1,y1,rgb) draws a rectangle."""
    rows = []
    for y in range(h):
        r = bytearray()
        for x in range(w):
            if x == 0 or y == 0 or x == w - 1 or y == h - 1:
                c = border
            elif inner and inner[0] <= x < inner[2] and inner[1] <= y < inner[3]:
                c = inner[4]
            else:
                c = fill
            r += bytes((c[2], c[1], c[0]))
        r += b"\x00" * ((-len(r)) % 4)
        rows.append(bytes(r))
    pixels = b"".join(rows)
    file_header = struct.pack("<2sIHHI", b"BM", 54 + len(pixels), 0, 0, 54)
    dib = struct.pack("<IiiHHIIiiII", 40, w, h, 1, 24, 0, len(pixels), 2835, 2835, 0, 0)
    path.write_bytes(file_header + dib + pixels)


# ---------------------------------------------------------------------------
# chart model
# ---------------------------------------------------------------------------

SLOTS = 16  # resolution of every note channel line (16th notes)


class Chart:
    def __init__(self, header: list[str]):
        self.header = list(header)
        self.notes: dict[tuple[int, int], list[str]] = {}
        self.raw: list[tuple[int, str, str]] = []  # (measure, channel-string, data)

    def note(self, measure: int, channel: int, slot: int, obj: str) -> None:
        key = (measure, channel)
        arr = self.notes.setdefault(key, ["00"] * SLOTS)
        if arr[slot] != "00":
            raise ValueError(f"slot collision at measure {measure} ch {channel} slot {slot}")
        arr[slot] = obj

    def line(self, measure: int, channel: str, data: str) -> None:
        self.raw.append((measure, channel, data))

    def body_lines(self) -> list[str]:
        out = []
        entries = [(m, ch, "".join(arr)) for (m, ch), arr in self.notes.items()]
        entries = [(m, "%02d" % ch, d) for m, ch, d in entries] + self.raw
        for m, ch, d in sorted(entries, key=lambda e: (e[0], e[1], e[2])):
            out.append("#%03d%s:%s" % (m, ch, d))
        return out

    def render(self, extra_tail: list[str] | None = None) -> str:
        lines = list(self.header) + [""] + ["*---------------------- MAIN DATA FIELD", ""]
        lines += self.body_lines()
        if extra_tail:
            lines += extra_tail
        return CRLF.join(lines) + CRLF


def base36_to_int(ch1: str, ch2: str) -> int:
    """En_fileutil.cpp Base36ToInt: 'a'-'z' and 'A'-'Z' are 10-35, '1'-'9' are 1-9, anything else 0."""
    def digit(c: str) -> int:
        if "a" <= c <= "z":
            return ord(c) - ord("a") + 10
        if "1" <= c <= "9":
            return ord(c) - ord("0")
        if "A" <= c <= "Z":
            return ord(c) - ord("A") + 10
        return 0
    return digit(ch1) * 36 + digit(ch2)


def songmanage_notes(text: str) -> float:
    """Port of the note count in LR2_songmanage.cpp ParseBMSMETA (2991-3082), run on the chart text.

    - lines inside any #IF other than "#IF 1" are skipped until #ENDIF (2991-2996)
    - #LNOBJ objects are not counted (3018-3022, 3070)
    - raw channels 51-69 are shifted by -40 and 31-49 by -20 before the check (3037-3043),
      so LN endpoints and hidden notes each count as 1 on 11-29 (the 0.5 branch is unreachable)
    """
    notes = 0.0
    flag_if = False
    lnobj = -12345
    for line in text.splitlines():
        if line.startswith("#IF") and not line.startswith("#IF 1"):
            flag_if = True
        elif line.startswith("#ENDIF"):
            flag_if = False
        elif not line.startswith("#") or flag_if:
            pass
        elif line.startswith("#LNOBJ"):
            lnobj = base36_to_int(line[7:8], line[8:9])
        elif len(line) > 5 and all(c in "0123456789" for c in line[1:6]):
            data = int(line[4]) * 10 + int(line[5])
            if 51 <= data <= 69:
                data -= 40
            if 31 <= data <= 49:
                data -= 20
            weight = 1.0 if 11 <= data <= 29 else 0.5 if 51 <= data <= 69 else 0.0
            if weight:
                body = line[7:]
                for i in range(0, len(body) - 1, 2):
                    obj = base36_to_int(body[i], body[i + 1])
                    if obj and obj != lnobj:
                        notes += weight
    return notes


def header(title: str, artist: str, genre: str, *, player: int, bpm, playlevel: int,
           rank: int, total: int, difficulty: int, extra: list[str] | None = None,
           wavs: dict[str, str] | None = None, bmps: dict[str, str] | None = None,
           stagefile: str | None = None, banner: str | None = None) -> list[str]:
    h = [
        "*---------------------- HEADER FIELD",
        "",
        f"#PLAYER {player}",
        f"#GENRE {genre}",
        f"#TITLE {title}",
        f"#ARTIST {artist}",
        f"#BPM {bpm}",
        f"#PLAYLEVEL {playlevel}",
        f"#RANK {rank}",
        f"#TOTAL {total}",
        f"#DIFFICULTY {difficulty}",
    ]
    if stagefile:
        h.append(f"#STAGEFILE {stagefile}")
    if banner:
        h.append(f"#BANNER {banner}")
    if extra:
        h += extra
    h.append("")
    for k, v in (wavs or {}).items():
        h.append(f"#WAV{k} {v}")
    h.append("")
    for k, v in (bmps or {}).items():
        h.append(f"#BMP{k} {v}")
    return h


# keysound slot numbers (all < 36 so they decode identically in base 36 and 62)
K = {i: idx(i) for i in range(1, 17)}  # k01..k16 -> "01".."0G"
BGM_IDX = idx(17)  # "0H"
MUON_IDX = idx(18)  # "0I"
BMP_BASE = [idx(i) for i in range(1, 5)]  # frame01..04 on channel 04
BMP_POOR = idx(5)  # frame05 on channel 06
BMP_LAYER = idx(6)  # frame06 on channel 07 (black background = transparent)

# base-62-only slots
B62_LOW = 36  # "0a": collides with "0A" (=10) under a base-36 parse
B62_BEYOND_ZZ = 36 * 62  # "a0" = 2232 > "ZZ" (2205)
B62_MAX = 62 * 62 - 1  # "zz" = 3843 = SINGLESLOTS-1 (structure.h:26)

# 7-key single play channels (sample_7.bme / channelConvert LR2_bmsload.cpp:21-298)
SP7 = {1: 11, 2: 12, 3: 13, 4: 14, 5: 15, 6: 18, 7: 19}
SP7_SC = 16
SP7_LN = {k: v + 40 for k, v in SP7.items()}  # 51,52,53,54,55,58,59
SP7_LN_SC = 56
SP5 = {1: 11, 2: 12, 3: 13, 4: 14, 5: 15}
PMS9 = {1: 11, 2: 12, 3: 13, 4: 14, 5: 15, 6: 22, 7: 23, 8: 24, 9: 25}
DP_2P7 = {1: 21, 2: 22, 3: 23, 4: 24, 5: 25, 6: 28, 7: 29}
DP_2P_SC = 26
DP_2P5 = {1: 21, 2: 22, 3: 23, 4: 24, 5: 25}


def wav_map(names: dict[str, str] | None = None, upper: bool = False) -> dict[str, str]:
    m = {K[i]: f"k{i:02d}.wav" for i in range(1, 17)}
    m[BGM_IDX] = "bgm.wav"
    m[MUON_IDX] = "muon.wav"
    if names:
        m.update(names)
    if upper:
        m = {k: v.upper() for k, v in m.items()}
    return m


def bmp_map(upper: bool = False) -> dict[str, str]:
    m = {BMP_BASE[i]: f"frame{i + 1:02d}.bmp" for i in range(4)}
    m[BMP_POOR] = "frame05.bmp"
    m[BMP_LAYER] = "frame06.bmp"
    if upper:
        m = {k: v.upper() for k, v in m.items()}
    return m


def fill_core_body(c: Chart, lanes: dict[int, int], sc: int, ln: dict[int, int], ln_sc: int,
                   lane2_obj: str | None = None, lane7_chord_obj: str | None = None,
                   sc_final_obj: str | None = None) -> None:
    """The 8-measure 7-key core pattern (120 BPM). Objects are k01..k16 slots unless overridden."""
    # measure 0: BGM + silent sample on channel 01, BGA base / poor / layer
    c.line(0, "01", BGM_IDX)
    c.line(0, "01", MUON_IDX)
    c.line(0, "04", BMP_BASE[0])
    c.line(0, "06", BMP_POOR)
    c.line(0, "07", BMP_LAYER)
    # measure 1: one note per lane on successive 8ths, scratch last
    for lane in range(1, 8):
        obj = lane2_obj if (lane == 2 and lane2_obj) else K[lane]
        c.note(1, lanes[lane], (lane - 1) * 2, obj)
    c.note(1, sc, 14, K[8])
    # measure 2: chords (simultaneous notes) incl. scratch
    c.line(2, "04", BMP_BASE[1])
    for lane in (1, 3, 5):
        c.note(2, lanes[lane], 0, K[lane])
    for lane in (2, 4, 6):
        c.note(2, lanes[lane], 4, K[lane])
    c.note(2, lanes[1], 8, K[1])
    c.note(2, lanes[7], 8, lane7_chord_obj or K[7])
    c.note(2, sc, 8, K[8])
    for lane in range(1, 8):
        c.note(2, lanes[lane], 12, K[lane])
    # measure 3: direct BPM change on channel 03 (hex 0x96 = 150) at the half bar
    c.line(3, "03", "0096")
    for s in range(0, 16, 2):
        c.note(3, lanes[1], s, K[9])
    c.note(3, lanes[4], 4, K[10])
    c.note(3, lanes[4], 12, K[10])
    # measure 4: #BPM01 (180) via channel 08 at the bar start, 16ths on lane 2
    c.line(4, "08", idx(1))
    c.line(4, "04", BMP_BASE[2])
    for s in range(16):
        c.note(4, lanes[2], s, K[11])
    c.note(4, sc, 0, K[8])
    c.note(4, sc, 8, K[8])
    # measure 5: back to #BPM02 (120) and a #STOP01 (96/192 bar = 1000 ms at 120 BPM) at the half bar
    c.line(5, "08", idx(2))
    c.line(5, "09", "0001")
    c.note(5, lanes[3], 0, K[12])
    c.note(5, lanes[5], 4, K[13])
    c.note(5, lanes[3], 8, K[12])  # lands exactly on the STOP
    c.note(5, lanes[5], 12, K[13])
    # measure 6: long notes on 5x channels (start/end pairs), plus a chord LN and a scratch LN
    c.note(6, ln[1], 0, K[14])
    c.note(6, ln[1], 12, K[14])
    c.note(6, ln[6], 0, K[15])
    c.note(6, ln[6], 12, K[15])
    c.note(6, ln[5], 8, K[16])
    c.note(6, ln[5], 15, K[16])
    c.note(6, ln_sc, 4, K[8])
    c.note(6, ln_sc, 10, K[8])
    c.note(6, lanes[3], 4, K[3])
    c.note(6, lanes[3], 8, K[3])
    c.line(6, "04", BMP_BASE[3])
    # measure 7: 3/4 bar (#xxx02), final chord, final scratch, BGA back to frame 1
    c.line(7, "02", "0.75")
    c.line(7, "04", BMP_BASE[0])
    for lane in range(1, 8):
        c.note(7, lanes[lane], 0, K[lane])
    c.note(7, sc, 6, sc_final_obj or K[8])
    c.note(7, lanes[4], 9, K[4])


def chart_7key_core(title_suffix: str = "", *, upper: bool = False, lane2_wav: str | None = None,
                    title: str | None = None, artist: str | None = None, genre: str | None = None) -> Chart:
    wavs = wav_map({K[2]: lane2_wav} if lane2_wav else None, upper=upper)
    c = Chart(header(
        title or f"[QA] 7key core{title_suffix}", artist or "synthetic", genre or "QA",
        player=1, bpm=120, playlevel=5, rank=2, total=300, difficulty=2,
        extra=["#LNTYPE 1", "#BPM01 180", "#BPM02 120", "#STOP01 96"],
        wavs=wavs, bmps=bmp_map(upper=upper),
        stagefile="STAGEFILE.BMP" if upper else "stagefile.bmp",
        banner="BANNER.BMP" if upper else "banner.bmp"))
    fill_core_body(c, SP7, SP7_SC, SP7_LN, SP7_LN_SC)
    return c


def chart_7key_base62() -> Chart:
    wavs = wav_map({
        idx(B62_LOW, 62): "k_0a.wav",
        idx(B62_BEYOND_ZZ, 62): "k_a0.wav",
        idx(B62_MAX, 62): "k_zz.wav",
    })
    # "0A" (=10) is k10; "0a" (=36) is k_0a. Under a base-36 misparse both decode to 10.
    c = Chart(header(
        "[QA] 7key base62", "synthetic", "QA", player=1, bpm=120, playlevel=5, rank=2,
        total=300, difficulty=2,
        extra=["#BASE 62", "#LNTYPE 1", "#BPM01 180", "#BPM02 120", "#STOP01 96"],
        wavs=wavs, bmps=bmp_map(), stagefile="stagefile.bmp", banner="banner.bmp"))
    fill_core_body(c, SP7, SP7_SC, SP7_LN, SP7_LN_SC,
                   lane2_obj=idx(B62_LOW, 62),  # measure 1 lane 2 -> k_0a (collides with k10 if base36)
                   lane7_chord_obj=idx(B62_BEYOND_ZZ, 62),  # measure 2 lane 7 -> k_a0 (index > ZZ)
                   sc_final_obj=idx(B62_MAX, 62))  # measure 7 scratch -> k_zz (index 3843)
    c.note(1, SP7[3], 5, idx(10))  # extra k10 right after lane 2 so the collision is audible
    return c


def chart_7key_lnobj() -> Chart:
    """Same LN shapes as the core chart measure 6, but expressed with #LNOBJ on normal channels."""
    c = Chart(header(
        "[QA] 7key lnobj", "synthetic", "QA", player=1, bpm=120, playlevel=4, rank=2,
        total=200, difficulty=2, extra=[f"#LNOBJ {idx(35)}"],
        wavs=wav_map({idx(35): "muon.wav"}), bmps=None))
    c.line(0, "01", BGM_IDX)
    end = idx(35)  # "0Z" terminator object (plays muon.wav)
    for m in (1, 2):
        c.note(m, SP7[1], 0, K[14])
        c.note(m, SP7[1], 12, end)
        c.note(m, SP7[6], 0, K[15])
        c.note(m, SP7[6], 12, end)
        c.note(m, SP7[5], 8, K[16])
        c.note(m, SP7[5], 15, end)
        c.note(m, SP7_SC, 4, K[8])
        c.note(m, SP7_SC, 10, end)
        c.note(m, SP7[3], 4, K[3])
        c.note(m, SP7[3], 8, K[3])
    for lane in range(1, 8):
        c.note(3, SP7[lane], 0, K[lane])
    return c


def chart_7key_scroll() -> Chart:
    c = Chart(header(
        "[QA] 7key scroll", "synthetic", "QA", player=1, bpm=120, playlevel=4, rank=2,
        total=200, difficulty=2,
        extra=["#SCROLL01 0.5", "#SCROLL02 2.0", "#SCROLL03 1.0"],
        wavs=wav_map(), bmps=None))
    c.line(0, "01", BGM_IDX)
    c.line(2, "SC", idx(1))  # half speed from measure 2
    c.line(4, "SC", idx(2))  # double speed from measure 4
    c.line(6, "SC", idx(3))  # normal from measure 6
    for m in range(1, 8):
        for lane in range(1, 8):
            c.note(m, SP7[lane], (lane - 1) * 2, K[lane])
        c.note(m, SP7_SC, 14, K[8])
    return c


def chart_7key_random() -> Chart:
    c = Chart(header(
        "[QA] 7key random", "synthetic", "QA", player=1, bpm=120, playlevel=4, rank=2,
        total=200, difficulty=2, wavs=wav_map(), bmps=None))
    # Common part BEFORE #RANDOM: LR2_bmsload.cpp:2317-2320 sets ifOn=0 at #RANDOM, so
    # lines between #RANDOM and the first matching #IF would be dropped.
    c.line(0, "01", BGM_IDX)
    for lane in range(1, 8):
        c.note(1, SP7[lane], (lane - 1) * 2, K[lane])
    c.note(1, SP7_SC, 14, K[8])
    branch_a = Chart([])
    branch_b = Chart([])
    for m in (2, 3):
        for lane in range(1, 8):
            branch_a.note(m, SP7[lane], (lane - 1) * 2, K[lane])
            branch_b.note(m, SP7[8 - lane], (lane - 1) * 2, K[8 - lane])  # mirrored lanes
        branch_a.note(m, SP7_SC, 14, K[8])
        branch_b.note(m, SP7_SC, 15, K[8])
    tail = ["#RANDOM 2", "#IF 1"] + branch_a.body_lines() + ["#ENDIF", "#IF 2"] + branch_b.body_lines() + ["#ENDIF"]
    # common part after #ENDIF (ifOn=1 again)
    for lane in range(1, 8):
        tail.append("#%03d%02d:%s" % (4, SP7[lane], K[lane] + "00" * 15))
    c._tail = tail  # type: ignore[attr-defined]
    return c


def chart_5key() -> Chart:
    c = Chart(header("[QA] 5key", "synthetic", "QA", player=1, bpm=120, playlevel=3, rank=2,
                     total=160, difficulty=1, wavs=wav_map(), bmps=None))
    c.line(0, "01", BGM_IDX)
    for m in range(1, 5):
        for lane in range(1, 6):
            c.note(m, SP5[lane], (lane - 1) * 3, K[lane])
        c.note(m, SP7_SC, 15, K[8])
        if m == 3:
            for lane in (1, 3, 5):
                c.note(m, SP5[lane], 1, K[lane])  # chord
    c.note(4, SP5[1] + 40, 8, K[14])
    c.note(4, SP5[1] + 40, 14, K[14])  # one LN on channel 51
    return c


def chart_9key_pms() -> Chart:
    # sample_9.pms ships #PLAYER 3 and channels 11-15 + 22-25 (channelConvert isPMS: 22->16 .. 25->19)
    c = Chart(header("[QA] 9key pms", "synthetic", "QA", player=3, bpm=120, playlevel=3, rank=2,
                     total=200, difficulty=1, wavs=wav_map(), bmps=None))
    c.line(0, "01", BGM_IDX)
    for m in range(1, 5):
        for btn in range(1, 10):
            c.note(m, PMS9[btn], (btn - 1) % 16, K[btn])
        if m == 3:
            for btn in (1, 5, 9):
                c.note(m, PMS9[btn], 12, K[btn])  # chord
    c.note(4, PMS9[9] + 40, 10, K[14])
    c.note(4, PMS9[9] + 40, 15, K[14])  # LN on channel 65 (-> 59)
    return c


def chart_10key_dp() -> Chart:
    c = Chart(header("[QA] 10key dp", "synthetic", "QA", player=3, bpm=120, playlevel=3, rank=2,
                     total=240, difficulty=1, wavs=wav_map(), bmps=None))
    c.line(0, "01", BGM_IDX)
    for m in range(1, 5):
        for lane in range(1, 6):
            c.note(m, SP5[lane], (lane - 1) * 3, K[lane])
            c.note(m, DP_2P5[lane], (lane - 1) * 3 + 1, K[lane + 8])
        c.note(m, SP7_SC, 15, K[8])
        c.note(m, DP_2P_SC, 15, K[16])  # simultaneous both scratches
    c.note(4, DP_2P5[3] + 40, 8, K[14])
    c.note(4, DP_2P5[3] + 40, 14, K[14])  # LN on channel 63
    return c


def chart_14key_dp() -> Chart:
    c = Chart(header("[QA] 14key dp", "synthetic", "QA", player=3, bpm=120, playlevel=5, rank=2,
                     total=300, difficulty=2, wavs=wav_map(), bmps=None))
    c.line(0, "01", BGM_IDX)
    for m in range(1, 5):
        for lane in range(1, 8):
            c.note(m, SP7[lane], (lane - 1) * 2, K[lane])
            c.note(m, DP_2P7[lane], (lane - 1) * 2 + 1, K[lane + 8])
        c.note(m, SP7_SC, 14, K[8])
        c.note(m, DP_2P_SC, 14, K[16])
    c.note(4, DP_2P7[7] + 40, 8, K[15])
    c.note(4, DP_2P7[7] + 40, 14, K[15])  # LN on channel 69 (-> 67)
    return c


def chart_missing_refs() -> Chart:
    c = Chart(header("[QA] broken missing refs", "synthetic", "QA", player=1, bpm=120, playlevel=1,
                     rank=2, total=100, difficulty=1,
                     wavs={"01": "missing_keysound.wav", "02": "k01.wav"},
                     bmps={"01": "missing_bga.bmp"},
                     stagefile="missing_stage.bmp", banner="missing_banner.bmp"))
    c.line(0, "04", "01")
    for m in range(1, 3):
        c.note(m, SP7[1], 0, "01")
        c.note(m, SP7[2], 4, "02")
        c.note(m, SP7[3], 8, "01")
        c.note(m, SP7_SC, 12, "02")
    return c


def chart_bpm_zero() -> Chart:
    c = Chart(header("[QA] broken bpm zero", "synthetic", "QA", player=1, bpm=0, playlevel=1,
                     rank=2, total=100, difficulty=1, wavs={"01": "k01.wav"}, bmps=None))
    for m in range(1, 3):
        c.note(m, SP7[1], 0, "01")
        c.note(m, SP7[2], 8, "01")
    return c


def chart_truncated_source() -> Chart:
    c = Chart(header("[QA] broken truncated", "synthetic", "QA", player=1, bpm=120, playlevel=1,
                     rank=2, total=100, difficulty=1, wavs={"01": "k01.wav"}, bmps=None))
    for m in range(1, 3):
        for lane in range(1, 8):
            c.note(m, SP7[lane], (lane - 1) * 2, "01")
    return c


# ---------------------------------------------------------------------------
# generation
# ---------------------------------------------------------------------------

SEMITONE = 2.0 ** (1.0 / 12.0)


def key_pitches() -> dict[int, float]:
    # k01..k16: A3 (220 Hz) upward in whole tones, so neighbouring slots are clearly distinct
    return {i: 220.0 * (SEMITONE ** (2 * (i - 1))) for i in range(1, 17)}


class Output:
    def __init__(self, root: Path):
        self.root = root
        self.files: list[dict] = []
        self.rel_cache: dict[str, dict] = {}

    def add(self, path: Path, scenario: str) -> None:
        rel = path.relative_to(self.root).as_posix()
        data = path.read_bytes()
        self.files.append({
            "path": rel,
            "size": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
            "scenario": scenario,
        })


def write_text(path: Path, text: str, encoding: str) -> None:
    path.write_bytes(text.encode(encoding))


def write_keysound_set(folder: Path, out: Output, scenario: str, rng: random.Random,
                       *, with_base62: bool = False, with_bga: bool = True,
                       extra_tone_names: dict[str, int] | None = None) -> None:
    pitches = key_pitches()
    for i in range(1, 17):
        p = folder / f"k{i:02d}.wav"
        write_tone(p, pitches[i])
        out.add(p, scenario)
    for name, src in (extra_tone_names or {}).items():
        p = folder / name
        write_tone(p, pitches[src])
        out.add(p, scenario)
    if with_base62:
        for name, freq in (("k_0a.wav", 110.0), ("k_a0.wav", 1760.0), ("k_zz.wav", 3520.0)):
            p = folder / name
            write_tone(p, freq)
            out.add(p, scenario)
    p = folder / "bgm.wav"
    write_bgm(p, rng)
    out.add(p, scenario)
    p = folder / "muon.wav"
    write_silence(p)
    out.add(p, scenario)
    if with_bga:
        colors = [tuple(rng.randrange(40, 220) for _ in range(3)) for _ in range(4)]
        for i, col in enumerate(colors, start=1):
            p = folder / f"frame{i:02d}.bmp"
            write_bmp(p, 64, 48, col, (255, 255, 255))
            out.add(p, scenario)
        p = folder / "frame05.bmp"  # POOR frame: red with white border
        write_bmp(p, 64, 48, (200, 30, 30), (255, 255, 255))
        out.add(p, scenario)
        p = folder / "frame06.bmp"  # LAYER frame: black (transparent) with a colored box
        write_bmp(p, 64, 48, (0, 0, 0), (0, 0, 0), inner=(20, 14, 44, 34, (30, 220, 60)))
        out.add(p, scenario)
        p = folder / "stagefile.bmp"
        write_bmp(p, 64, 48, (60, 60, 120), (255, 255, 255))
        out.add(p, scenario)
        p = folder / "banner.bmp"
        write_bmp(p, 60, 16, (120, 60, 60), (255, 255, 255))
        out.add(p, scenario)


def generate(out_root: Path, seed: int) -> tuple[Output, list[dict]]:
    out = Output(out_root)
    summary: list[dict] = []
    syn = out_root

    def chart_file(folder: Path, name: str, chart: Chart, scenario: str, encoding: str = "utf-8",
                   text: str | None = None) -> None:
        p = folder / name
        body = text if text is not None else chart.render(getattr(chart, "_tail", None))
        write_text(p, body, encoding)
        out.add(p, scenario)
        summary.append({
            "scenario": scenario,
            "chart": p.relative_to(out_root).as_posix(),
            "encoding": encoding,
            "expected_notes": songmanage_notes(body),
        })

    # --- ascii_basic: every mode + feature chart ----------------------------
    folder = syn / FOLDER_ASCII
    folder.mkdir(parents=True)
    write_keysound_set(folder, out, "ascii_basic", random.Random(seed), with_base62=True)
    chart_file(folder, "7key_core.bms", chart_7key_core(), "core_7key")
    chart_file(folder, "7key_base62.bms", chart_7key_base62(), "base62")
    chart_file(folder, "7key_lnobj.bms", chart_7key_lnobj(), "lnobj")
    chart_file(folder, "7key_scroll.bms", chart_7key_scroll(), "scroll")
    chart_file(folder, "7key_random.bms", chart_7key_random(), "random")
    chart_file(folder, "5key.bms", chart_5key(), "mode_5key")
    chart_file(folder, "9key.pms", chart_9key_pms(), "mode_9key")
    chart_file(folder, "10key_dp.bms", chart_10key_dp(), "mode_10key")
    chart_file(folder, "14key_dp.bme", chart_14key_dp(), "mode_14key")

    # --- i18n: Japanese folder (space in name), UTF-8 + CP932 copies ----------
    folder = syn / FOLDER_JA
    folder.mkdir()
    write_keysound_set(folder, out, "i18n_ja", random.Random(seed),
                       extra_tone_names={"鍵音02.wav": 2})
    ja = dict(title="[QA] 7key 合成テスト曲（日本語）", artist="合成 太郎", genre="テスト")
    chart_file(folder, "7key_core_ja_utf8.bms",
               chart_7key_core(lane2_wav="鍵音02.wav", **ja), "i18n_ja", "utf-8")
    chart_file(folder, "7key_core_ja_cp932.bms",
               chart_7key_core(lane2_wav="鍵音02.wav", **ja), "i18n_ja", "cp932")

    # --- i18n: Korean folder (space in name), UTF-8 only (Hangul is not representable in CP932)
    folder = syn / FOLDER_KO
    folder.mkdir()
    write_keysound_set(folder, out, "i18n_ko", random.Random(seed),
                       extra_tone_names={"건반02.wav": 2})
    ko = dict(title="[QA] 7key 합성 테스트 곡 (한국어)", artist="합성 작곡가", genre="테스트")
    chart_file(folder, "7key_core_ko_utf8.bms",
               chart_7key_core(lane2_wav="건반02.wav", **ko), "i18n_ko", "utf-8")

    # --- case_mismatch: chart references UPPER-case names, files are lower-case
    folder = syn / FOLDER_CASE
    folder.mkdir()
    write_keysound_set(folder, out, "case_mismatch", random.Random(seed))
    chart_file(folder, "7key_core_upper.bms", chart_7key_core(" (UPPER refs)", upper=True), "case_mismatch")

    # --- broken: must not crash the game -------------------------------------
    folder = syn / FOLDER_BROKEN
    folder.mkdir()
    p = folder / "k01.wav"
    write_tone(p, key_pitches()[1])
    out.add(p, "broken")
    chart_file(folder, "missing_refs.bms", chart_missing_refs(), "broken_missing_refs")
    chart_file(folder, "bpm_zero.bms", chart_bpm_zero(), "broken_bpm_zero")
    full = chart_truncated_source().render()
    cut = full.rstrip("\r\n")[:-5]  # last data line ends mid-object, no trailing newline
    chart_file(folder, "truncated.bms", chart_truncated_source(), "broken_truncated", text=cut)
    chart_file(folder, "empty.bms", Chart([]), "broken_empty", text="")

    return out, summary


def write_manifest(out: Output, seed: int, summary: list[dict]) -> Path:
    files = sorted(out.files, key=lambda f: f["path"])
    manifest = {
        "generator": "make_synthetic_charts.py",
        "generator_version": GENERATOR_VERSION,
        "seed": seed,
        "file_count": len(files),
        "total_bytes": sum(f["size"] for f in files),
        "charts": sorted(summary, key=lambda s: s["chart"]),
        "files": files,
    }
    p = out.root / "manifest.json"
    # bytes, not write_text: newline translation would make the manifest hash differ per OS
    p.write_bytes((json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8"))
    return p


def print_summary(out: Output, summary: list[dict], manifest_path: Path) -> None:
    by_scenario: dict[str, list[dict]] = {}
    for f in out.files:
        by_scenario.setdefault(f["scenario"], []).append(f)
    print()
    print("%-22s %6s %10s" % ("scenario", "files", "bytes"))
    print("-" * 40)
    for sc in sorted(by_scenario):
        fs = by_scenario[sc]
        print("%-22s %6d %10d" % (sc, len(fs), sum(f["size"] for f in fs)))
    print("-" * 40)
    print("%-22s %6d %10d" % ("total", len(out.files), sum(f["size"] for f in out.files)))
    print()
    print("%-52s %-6s %s" % ("chart", "enc", "expected_notes(songmanage)"))
    print("-" * 90)
    for s in sorted(summary, key=lambda s: s["chart"]):
        print("%-52s %-6s %g" % (s["chart"], s["encoding"], s["expected_notes"]))
    print()
    print(f"manifest: {manifest_path}")


def main(argv: list[str] | None = None) -> int:
    repo = Path(__file__).resolve().parents[3]
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=repo / ".local" / "qa" / "synthetic",
                    help="output root (default: <repo>/.local/qa/synthetic, gitignored)")
    ap.add_argument("--seed", type=int, default=DEFAULT_SEED, help="seed for BGA colours and BGM note order")
    ap.add_argument("--force", action="store_true", help="remove an existing synthetic/ tree and manifest.json first")
    args = ap.parse_args(argv)

    out_root: Path = args.out.resolve()
    existing = [out_root / name for name in SONG_FOLDERS] + [out_root / "manifest.json"]
    present = [p for p in existing if p.exists()]
    if present:
        if not args.force:
            print(f"error: {out_root} already contains generated output ({present[0].name}); "
                  "re-run with --force to replace it", file=sys.stderr)
            return 2
        for p in present:  # only the folders this script creates are ever removed
            if p.is_dir():
                shutil.rmtree(p)
            else:
                p.unlink()
    out_root.mkdir(parents=True, exist_ok=True)

    out, summary = generate(out_root, args.seed)
    manifest_path = write_manifest(out, args.seed, summary)
    print_summary(out, summary, manifest_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
