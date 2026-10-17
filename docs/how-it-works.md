# How Offscript works

How it follows your voice, saved scripts, permissions, requirements, building it and shortcuts. The short version is the [README](../README.md).

## How it follows you

Paste your script into the floating window and press play. After a 3-2-1 countdown the app starts listening via the macOS speech recognizer, matches what you say to positions in the script, and scrolls so your current line stays near the top. Pause, rephrase, or skip ahead and the matcher catches up within a few words. Text in [brackets], like [pause] or [show the demo], stays on screen as a note to yourself and is never waited for.

The window stays above full-screen apps and crosses Spaces. It is hidden from screen sharing and screenshots by default, so it does not appear in the recording. Speech recognition runs on your Mac when macOS supports it, falling back to Apple's speech servers otherwise, and works with the built-in microphone, AirPods, and other Bluetooth inputs. It keeps following for as long as you talk: recognition restarts every 55 seconds, before macOS would end the session, without dropping your voice, and it is primed with upcoming words from your script so names and jargon are heard correctly.

Offscript is useful for tutorials, talking-head videos, pitch recordings, and product walkthroughs where you want to keep your eyes close to the camera while following a prepared script.

## Saved scripts

Offscript reopens the script you had on screen when you last quit. The five most recently used scripts are in the scripts menu (the page icon in the control bar), along with **New Script** and the built-in **Practice Script**. Typing edits the current script; pasting over all of it, or clearing it, starts a new one so the old script stays in the list. Scripts are saved as one JSON file in the app's Application Support folder (`~/Library/Containers/com.san.Cue/Data/Library/Application Support/Offscript/scripts.json`) and never leave your Mac.

## Fonts and themes

The palette button in the control bar opens font, text size, theme and opacity; Settings (⌘,) has the same controls. The fonts all ship with macOS: System, Rounded, Serif (New York), Monospaced, Avenir Next, Helvetica Neue, Georgia and Charter. The themes are Match System, Dark, Light, Sepia, Midnight, Classic (yellow text on black), Yellow (black text on yellow) and Blue. Match System switches between Light and Dark with your Mac, and opacity applies to every theme.

## Permissions

The first time you press play, macOS asks for Microphone access and, once you answer, for Speech Recognition; the countdown starts when both are allowed. The two prompts are asked one after the other because asking for both at once, or asking while a menu is closing, could leave a prompt that never appeared. The menu bar item shows both states and can ask again. If either is turned off, the window shows which one with an **Open Settings** button for the right Privacy & Security page, and the warning clears when you come back with it turned on.

## Requirements

- macOS 14 (Sonoma) or later (tested on macOS 26.3)
- Microphone access and Speech Recognition access
- Siri & Dictation enabled in System Settings
- AirPods or Bluetooth mics work via the AVCaptureSession path

## Running it

```bash
git clone https://github.com/madebysan/offscript.git
cd offscript

# Regenerate the Xcode project if you edit project.yml
/opt/homebrew/bin/xcodegen generate

# Build
xcodebuild \
  -project Cue.xcodeproj \
  -scheme Cue \
  -destination 'platform=macOS' \
  build

# Launch
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Offscript.app" -path "*Debug*" | head -1)
open "$APP_PATH"
```

Or open `Cue.xcodeproj` in Xcode and press ⌘R.

## Testing with an audio file

Debug builds can follow a recording instead of the microphone, so tracking can be tested without reading aloud. The audio plays straight into speech recognition at normal speed (muted unless you add `--test-aloud`), and two files are written when it ends: `<script>-positions.csv`, with the prompter's word position over time, and `<script>-heard.txt`, with what was recognized. The sandboxed debug build can only reach `~/Projects/offscript/test-audio/` (git-ignored), so the audio, scripts and results go there.

```bash
/tmp/offscript-dd/Build/Products/Debug/Offscript.app/Contents/MacOS/Offscript \
  --test-audio ~/Projects/offscript/test-audio/clip.m4a \
  --test-script ~/Projects/offscript/test-audio/script.txt \
  --test-hidden --test-quit
```

`--test-hidden` keeps the window invisible and leaves focus alone; `--test-quit` quits when the audio ends; `--test-results DIR` changes where results go. Launch it with `open -n <app> --args …` if running the binary directly is refused. Useful variations: remove paragraphs from the script (the prompter should hold, then pick up), add paragraphs the audio never says (it should skip past), and add [bracketed] notes (it should never wait on them).

For many variations at once, [scripts/tracking-tests](../scripts/tracking-tests/README.md) records what recognition hears once per audio file and replays it against dozens of script variants in about two minutes (`CueTests/ReplayTests`), writing a scorecard. On 2026-10-17 all 43 scenarios across five speakers passed: the prompter trailed the speaker by a median of 2 to 3 words, found skips of any length within 1 to 3.5 seconds of speech, and was undone within seconds the few times it jumped ahead wrongly.

## Known limits

- It only follows you forward. If you go back to reread a line, it waits where it is until you reach new text; use ↑ to move it back.
- If you say a sentence that appears word for word later in the script, it may jump there; it comes back once you carry on reading where you were.

## Keyboard shortcuts

- **Space.** Start / pause.
- **Escape.** Pause.
- **↑ / ↓.** Nudge position manually (5 words back / forward).
- **⌘,** opens Settings: font, text size, theme and opacity.
- **⌘Q** quits.
