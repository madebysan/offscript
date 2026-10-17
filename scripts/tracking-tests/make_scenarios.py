#!/usr/bin/env python3
"""Build tracking-test scenarios from word-timed transcripts.

Reads Parakeet JSON word timings from <data>/timings/, writes:
  <data>/record-scripts/<recording>.txt  the script loaded while recording, so
                                         recognition gets the same hints
  <data>/scenarios/<name>.json           one script variant per scenario, with
                                         "marks": [seconds, utf16 end offset]
                                         saying when the speaker finished each
                                         script word

The replay tests (CueTests/ReplayTests.swift) feed a recording's recognition
results into the matcher against each scenario's script and score how closely
the prompter followed the marks. <data> defaults to test-audio/ in the repo.
"""

from __future__ import annotations

import json
import random
import sys
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DATA = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "test-audio"

# How each recording's audio was cut from its source: (source start, source end,
# output start), in seconds. Anything outside these spans isn't the script's speaker.
RECORDINGS: dict[str, tuple[str, list[tuple[float, float, float]], float]] = {
    "bevel-full": ("bevel-whoop", [(0, 629, 0)], 629),
    "bevel-silence": ("bevel-whoop", [(0, 60, 0), (60, 210, 90)], 240),  # 30 s pause at 1:00
    "bevel-adlib": ("bevel-whoop", [(0, 90, 0), (90, 210, 115)], 235),  # 25 s of another speaker at 1:30
    "bevel-reread": ("bevel-whoop", [(0, 60, 0), (45, 60, 60), (60, 210, 75)], 225),  # rereads 0:45-1:00
    "ted-robinson": ("ted-robinson", [(0, 240, 0)], 240),
    "ted-rosling": ("ted-rosling", [(0, 240, 0)], 240),
    "mkbhd": ("mkbhd", [(0, 240, 0)], 240),
    "ramsay": ("ramsay", [(0, 240, 0)], 240),
}
# Script variants run against these; the bevel audio variants use the plain script.
VARIANT_RECORDINGS = ["bevel-full", "ted-robinson", "ted-rosling", "mkbhd", "ramsay"]

FILLER = (
    "On Saturday we drove up the coast and hiked to the old lighthouse. The trail was muddy, "
    "the dog found every puddle, and we stopped at a tiny bakery for cinnamon rolls. "
    "On the way home the car got a flat tire in the rain, so we waited an hour for help. "
    "Later I tried a new pasta recipe with lemon, garlic and far too much parmesan. "
    "My neighbor lent me a ladder to clean the gutters, and I found a tennis ball from last summer. "
    "The library was closed on Monday, so I read the newspaper on the porch instead. "
    "Our plants finally recovered after the heat wave, especially the tomatoes and basil. "
    "We spent the evening sorting old photos into albums and laughing at the haircuts. "
    "The bus was late again, which gave me time to finish a crossword puzzle at the stop. "
    "Next month we plan to paint the kitchen a pale green and replace the squeaky door."
).split()

PARAPHRASE = ["really", "basically", "actually", "simply", "certainly", "probably", "somehow", "usually"]


@dataclass
class Word:
    text: str  # as written, with attached punctuation
    start: float
    end: float
    sentence_end: bool


@dataclass
class Piece:
    """A run of script text; `spoken` words carry the time they were said."""

    text: str
    said_at: float | None = None


def load_words(source: str) -> list[Word]:
    data = json.loads((DATA / "timings" / f"{source}.json").read_text())
    words: list[Word] = []
    for sentence in data["sentences"]:
        current: Word | None = None
        for token in sentence["tokens"]:
            text = token["text"]
            if current is None or text.startswith(" "):
                if current:
                    words.append(current)
                current = Word(text.strip(), token["start"], token["end"], False)
            else:
                current.text += text
                current.end = token["end"]
        if current:
            current.sentence_end = True
            words.append(current)
    return [w for w in words if any(c.isalnum() for c in w.text)]


def to_output_time(t: float, spans: list[tuple[float, float, float]]) -> list[float]:
    """Every time a source moment is heard in the recording (twice when reread)."""
    return [out + (t - a) for a, b, out in spans if a <= t < b]


def paragraphs(words: list[Word], sentences_per_paragraph: int = 5) -> list[list[Word]]:
    result: list[list[Word]] = [[]]
    count = 0
    for w in words:
        result[-1].append(w)
        if w.sentence_end:
            count += 1
            if count % sentences_per_paragraph == 0:
                result.append([])
    return [p for p in result if p]


def utf16_len(s: str) -> int:
    return len(s.encode("utf-16-le")) // 2


def assemble(blocks: list[list[Piece]], spans: list[tuple[float, float, float]]) -> tuple[str, list[list[float]]]:
    """Joins paragraphs into a script and lists (time, utf16 end offset) marks."""
    text = ""
    marks: list[list[float]] = []
    for i, block in enumerate(blocks):
        if i:
            text += "\n\n"
        for j, piece in enumerate(block):
            if j:
                text += " "
            text += piece.text
            if piece.said_at is not None:
                end = utf16_len(text.rstrip(".,;:!?\"'"))
                for t in to_output_time(piece.said_at, spans):
                    marks.append([round(t, 2), end])
    marks.sort()
    return text, marks


def filler(count: int, seed: int) -> list[Piece]:
    rng = random.Random(seed)
    start = rng.randrange(len(FILLER))
    return [Piece(FILLER[(start + k) % len(FILLER)]) for k in range(count)]


def block_at(paras: list[list[Word]], fraction: float, limit: float) -> int:
    """Index of the first paragraph starting after `fraction` of the spoken audio."""
    target = fraction * limit
    for i, p in enumerate(paras):
        if p[0].start >= target:
            return i
    return len(paras) - 1


def typo(word: str) -> str:
    letters = [i for i, c in enumerate(word) if c.isalpha()]
    if len(letters) < 4:
        return word
    i = letters[len(letters) // 2]
    chars = list(word)
    chars[i], chars[i - 1] = chars[i - 1], chars[i]
    return "".join(chars)


def variants(paras: list[list[Word]], limit: float) -> dict[str, tuple[list[list[Piece]], str]]:
    spoken = [[Piece(w.text, w.end) for w in p] for p in paras]
    out: dict[str, tuple[list[list[Piece]], str]] = {"full": (spoken, "the script as spoken")}

    def with_insert(at: int, count: int) -> list[list[Piece]]:
        return spoken[:at] + [filler(count, seed=at)] + spoken[at:]

    out["skips-sentence"] = (with_insert(block_at(paras, 0.3, limit), 25), "script has a 25-word sentence the speaker skips")
    out["skips-paragraph"] = (with_insert(block_at(paras, 0.3, limit), 80), "script has an 80-word paragraph the speaker skips")
    out["skips-long"] = (with_insert(block_at(paras, 0.5, limit), 200), "script has 200 words the speaker skips")
    cut = block_at(paras, 0.4, limit)
    out["adlibs"] = (
        spoken[:cut] + spoken[cut + 1:],
        "speaker says a paragraph that isn't in the script",
    )
    out["typos"] = (
        [[Piece(typo(p.text), p.said_at) if k % 7 == 3 else p for k, p in enumerate(b)] for b in spoken],
        "every 7th word misspelled in the script",
    )
    out["paraphrase"] = (
        [
            [Piece(PARAPHRASE[k % len(PARAPHRASE)], p.said_at) if k % 6 == 2 and len(p.text) > 3 else p for k, p in enumerate(b)]
            for b in spoken
        ],
        "every 6th word in the script differs from what's said",
    )
    notes = ["[pause]", "[look at the camera]", "[show the demo]", "[smile, slow down]"]
    with_notes: list[list[Piece]] = []
    for i, b in enumerate(spoken):
        with_notes.append(b)
        if i % 2 == 1:
            with_notes.append([Piece(notes[i // 2 % len(notes)])])
    out["notes"] = (with_notes, "bracketed notes between paragraphs")
    return out


def main() -> None:
    (DATA / "record-scripts").mkdir(exist_ok=True)
    scenarios_dir = DATA / "scenarios"
    scenarios_dir.mkdir(exist_ok=True)
    for old in scenarios_dir.glob("*.json"):
        old.unlink()

    count = 0
    for recording, (source, spans, duration) in RECORDINGS.items():
        words = load_words(source)
        paras = paragraphs(words)
        plain = "\n\n".join(" ".join(w.text for w in p) for p in paras)
        (DATA / "record-scripts" / f"{recording}.txt").write_text(plain)

        limit = min(duration, max(b for _, b, _ in spans))
        chosen = variants(paras, limit) if recording in VARIANT_RECORDINGS else {"full": variants(paras, limit)["full"]}
        for variant, (blocks, note) in chosen.items():
            text, marks = assemble(blocks, spans)
            name = f"{recording}--{variant}"
            scenario = {
                "name": name,
                "recording": recording,
                "variant": variant,
                "note": note,
                "duration": duration,
                "script": text,
                "marks": marks,
            }
            (scenarios_dir / f"{name}.json").write_text(json.dumps(scenario))
            count += 1
    print(f"{count} scenarios in {scenarios_dir}")


if __name__ == "__main__":
    main()
