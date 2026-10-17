# Tracking tests

Checks how well Offscript follows a speaker, using real recordings instead of reading aloud. Everything these scripts download or produce goes in `test-audio/`, which git ignores: the audio belongs to its creators and stays on your Mac.

## How it works

1. **Audio.** Clips of real talks in `test-audio/` (for example `ted-robinson.m4a`), plus edited copies that add a 30-second pause, 25 seconds of another speaker, or a reread line.
2. **Truth.** Parakeet word timings for each source (`test-audio/timings/<source>.json`) say when the speaker finished every word.
3. **Scenarios.** `make_scenarios.py` writes script variants for each recording: the script as spoken, plus versions where the speaker skips a sentence, a paragraph or 200 words, ad-libs a paragraph, or the script has typos, different wording or [bracketed] notes. Each scenario lists when each of its words was said.
4. **Recordings.** `record.sh` plays each audio file straight into speech recognition through a debug build (no microphone, no sound) and saves every recognition result with its time to `test-audio/recordings/`. This runs in real time, once per audio file.
5. **Replay.** `CueTests/ReplayTests.swift` feeds each recording into the matcher against every scenario in a few seconds, and writes `test-audio/results/scorecard.md`. It fails when a scenario falls too far behind, runs ahead, or ends off; it's skipped when `test-audio/` has no scenarios.

## Running it

```bash
cd ~/Projects/offscript
python3 -I scripts/tracking-tests/make_scenarios.py
xcodebuild -project Cue.xcodeproj -scheme Cue -destination 'platform=macOS' -derivedDataPath /tmp/offscript-dd build
scripts/tracking-tests/record.sh
xcodebuild -project Cue.xcodeproj -scheme Cue -destination 'platform=macOS' -derivedDataPath /tmp/offscript-dd test -only-testing:CueTests/ReplayTests
```

After changing the matcher, only the last command is needed. Recording again is only needed after changing speech recognition itself.

## Limits of the method

Recognition was recorded with the plain script's words as hints; a variant's script would give slightly different hints in the app. The matcher is replayed on its own, so scrolling and the 55-second recognition restarts are covered by the recordings, not the replay. Getting the source audio (yt-dlp) and the word timings (`parakeet-mlx --output-format json`, into `test-audio/timings/`) is done by hand; the sources used so far are listed in `test-audio/TESTS.md`.
