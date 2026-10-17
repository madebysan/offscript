import Foundation

/// The built-in script shown on first launch, or when chosen from the scripts menu.
/// It walks through pacing, going off script and skipping ahead.
enum PracticeScript {
    static let text = """
    Welcome to Offscript, a teleprompter that listens to you instead of running on a timer. Start by pressing the spacebar or clicking the play button. A three-two-one countdown will appear, and then the app will begin listening. As you speak, the text will scroll to keep your current position visible. You do not need to match the speed to your reading pace. Just talk normally. The app will follow.

    You can test how well the matching works by changing your cadence. Try speaking quickly, then slowly. Try pausing for a full second between sentences. Try emphasizing certain words, then mumbling through others. The scroll should track you through all of these variations without getting confused. If the recognizer mishears a word, the fuzzy matching should still advance the position. If you stumble or backtrack, the scroll should hold steady rather than jump around.

    Now, try going off script. Stop reading these sentences and start talking about something completely different. Describe your day, or explain what you had for breakfast, or simply count to ten. The scroll will freeze in place because the words you are saying do not match anywhere in the script. When you return to reading the script, the position should resume exactly where you left off. This behavior is intentional. The app should never guess wildly when it does not know where you are.

    Next, try skipping ahead. Jump down two paragraphs and start reading from a different point. The app should notice that your spoken words match a location further down in the script, and the scroll should jump forward to catch up with you. This is the behavior you want when you deliver a talk from memory and only glance at the teleprompter occasionally. You set the pace. The app adapts.

    Let us talk about why this exists. Traditional teleprompters scroll at a fixed speed, measured in pixels per second or words per minute. The operator has to calibrate the speed for each speaker, and the speaker has to match the machine. If the operator sets the pace too fast, the speaker falls behind and looks frantic. If the operator sets it too slow, the speaker rushes ahead and waits awkwardly for the next line. Good teleprompter operators are rare and expensive because this calibration is a real craft.

    Speech recognition removes the operator from the loop. The app listens to what you are actually saying and moves the text to match. It works at any pace, adjusts to emphasis and pauses automatically, and never drifts out of sync over a long reading. The cost is that it requires a good microphone, a quiet room, and a language model that knows your accent. Apple's on-device speech recognition handles English, Spanish, French, German, Mandarin, Japanese, and a dozen other languages, all without sending your voice to a server.

    If you need to override the automatic tracking, you have several options. The up and down arrow keys will nudge the current position backward or forward by a few words. The escape key pauses everything immediately. Clicking inside this text area and using a trackpad or mouse wheel will scroll manually, though the app will try to re-center you the moment you start speaking again. If you want to edit the script while running, pause first, then click in and make your changes, then resume.

    Finally, a note on privacy. Offscript uses your microphone and Apple's speech recognition. Audio is processed locally when on-device recognition is available, and never stored. Your scripts stay on your machine. The window itself can be made invisible to screen recording and screen sharing, so you can rehearse during a video call without your audience seeing the prompter.

    You have reached the end of the test script. Congratulations. If the scroll tracked you all the way here without getting stuck, the app is working correctly. If it stuck partway, note where and let the developer know. Now go practice your actual script.
    """
}
