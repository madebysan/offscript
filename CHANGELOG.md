# Changelog

## 0.3.0 (2026-10-17)

- Steadier following: skips of any length are found within 1 to 3.5 seconds of speech; a phrase you just read no longer pulls the prompter to a later copy of it; a wrong jump is undone when you keep reading where you were; recognition stutters and script typos or rewording no longer stall it. A jump now needs a second result with newly heard words, not a repeat of the same one.
- Skipping ahead works for any distance. Before, the prompter only looked 40 words ahead, so skipping a longer paragraph left it stuck. When nothing nearby matches, it now searches the rest of the script for a five-word phrase and moves once two results agree.
- No Dock icon: Offscript lives in the menu bar, under a new retro microphone icon, so it stays out of sight when you share your screen. Settings, About and Check for Updates are in the menu bar menu and bring the app forward.
- A palette button in the window's control bar opens font, text size, theme and opacity, the same controls as Settings. Eight fonts that ship with macOS (System, Rounded, Serif, Monospaced, Avenir Next, Helvetica Neue, Georgia, Charter), text size from 12 to 72 pt, and eight themes: Match System, Dark, Light, Sepia, Midnight, Classic (yellow on black), Yellow (black on yellow) and Blue. Dark stays the default. The Settings tips are gone.
- Offscript reopens the script you had on screen when you last quit. A scripts menu in the control bar lists the five most recent scripts, plus New Script and the Practice Script. Pasting over a whole script starts a new one, so the old one stays in the list. Scripts are saved only on your Mac, in Application Support.
- Permission prompts appear reliably on first use: pressing play asks for the microphone, then for speech recognition once you answer, and the countdown starts when both are allowed. Before, the two could be asked at once (or while the menu bar menu was closing) and a prompt could fail to show.
- If the microphone or speech recognition is turned off, the window says which one and offers an Open Settings button for the right Privacy & Security page; the menu bar shows the live state of both.
- Renamed from Cue to Offscript: app name, menus, permission prompts, DMG and docs. The bundle ID (`com.san.Cue`), settings and log folder are unchanged, so an existing install keeps its permissions.
- Recognition restarts every 55 seconds while the microphone keeps listening, instead of waiting for macOS to end the session, so no words are lost at the one-minute mark.
- Upcoming words from the script (five letters or more) are passed to speech recognition, so names and jargon in the script are heard correctly.
- Smoother following: small steps move at once, but a bigger jump waits until two recent results agree, so the highlight no longer leaps on one stray match. Skipping ahead still works within a moment.
- Text in [brackets] is shown but never waited for, so scripts can carry cues like [pause].

## 0.2.0 (2026-10-12)

- Following no longer stops after about a minute: Cue starts a new speech recognition session whenever macOS ends one, for as long as you read.
- Speech recognition runs on your Mac when supported, switching to Apple's servers only if on-device recognition fails.
- Recognized speech is no longer written to the diagnostic log in release builds.
- Scrolling follows your reading pace and glides through each line instead of jumping a line at a time.
- The About window shows the app's real version.

## 0.1.0 (2026-04-20)

First release, as a signed and notarized DMG.

- A floating teleprompter pinned below the notch: borderless, dark, resizable, and remembered between launches.
- Invisible to screenshots, screen recordings and screen sharing.
- Follows your voice with Apple's speech recognition and a fuzzy matcher that tolerates misreadings, holds still when you go off script, and jumps ahead when you skip.
- One Play button with a 3-2-1 countdown; Space starts and pauses, Escape pauses, the arrow keys nudge the position.
- A menu bar extra with show/hide, microphone and speech permission status, Settings and Quit.
- Settings for background opacity and default text size.
- A built-in practice script that walks through pacing, going off script and skipping ahead.
