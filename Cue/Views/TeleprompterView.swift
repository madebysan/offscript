import AppKit
import SwiftUI

/// NSTextView-backed teleprompter surface. Supports editing, programmatic
/// scrolling to an exact character offset (for transcription-driven sync),
/// and arrow-key manual scroll.
struct TeleprompterView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor
    /// Character offset to keep visible (e.g. where the user currently is in the script).
    /// When nil, no programmatic scroll happens.
    var focusCharOffset: Int?
    /// Whether the editor is currently focused (for disabling spacebar-as-play).
    var onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onFocusChange: onFocusChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 24, height: 16)
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.autoresizingMask = [.width]
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            if selectedRange.location <= text.count {
                textView.setSelectedRange(selectedRange)
            }
            context.coordinator.lastScrolledOffset = -1  // text changed, re-scroll next time
        }
        if textView.font != font {
            textView.font = font
        }
        if textView.textColor != textColor {
            textView.textColor = textColor
            textView.insertionPointColor = textColor
        }

        // Only scroll when the offset actually changes — prevents layout loops from
        // rapid-fire SwiftUI re-renders during speech recognition.
        guard let offset = focusCharOffset,
              !context.coordinator.isFocused,
              !textView.string.isEmpty,
              offset >= 0,
              offset <= textView.string.count,
              offset != context.coordinator.lastScrolledOffset,
              let lm = textView.layoutManager,
              let tc = textView.textContainer
        else { return }

        context.coordinator.lastScrolledOffset = offset

        lm.ensureLayout(for: tc)
        let nsRange = NSRange(location: offset, length: offset < textView.string.utf16.count ? 1 : 0)
        let glyphRange = lm.glyphRange(forCharacterRange: nsRange, actualCharacterRange: nil)
        guard glyphRange.location != NSNotFound else { return }

        let rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        // Move continuously through each line: add the share of the line already read,
        // so the scroll creeps forward word by word instead of stepping a line at a time.
        let glyphIndex = min(glyphRange.location, max(0, lm.numberOfGlyphs - 1))
        let line = lm.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let progressInLine = line.width > 0 ? min(1, max(0, (rect.minX - line.minX) / line.width)) : 0
        let readingY = line.minY + progressInLine * line.height + textView.textContainerInset.height
        let visibleHeight = scrollView.contentView.bounds.height
        guard visibleHeight > 0 else { return }
        let targetTop = max(0, readingY - visibleHeight * 0.35)
        let maxY = max(0, textView.bounds.height - visibleHeight)
        let clamped = min(targetTop, maxY)
        // Follow at the reader's pace rather than jumping to each match
        context.coordinator.follow(to: clamped, lineHeight: textView.font.map { lm.defaultLineHeight(for: $0) } ?? 20, maxY: maxY)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var textBinding: Binding<String>
        var onFocusChange: (Bool) -> Void
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var isFocused: Bool = false
        var lastScrolledOffset: Int = -1

        // Pace-following scroll. Matches arrive in bursts (often a line at a time), so
        // between matches the view keeps moving at the reader's measured speed, and each
        // match gently corrects it. If matches stall, it keeps going at most about a line
        // and a half past the last match and waits there.
        private var confirmedY: CGFloat = 0
        private var confirmedAt = Date()
        private var speed: CGFloat = 0          // points per second, smoothed
        private var leadLimit: CGFloat = 10
        private var lineStep: CGFloat = 20
        private var scrollMaxY: CGFloat = 0
        private var glideTimer: Timer?

        func follow(to y: CGFloat, lineHeight: CGFloat, maxY: CGFloat) {
            let now = Date()
            let elapsed = CGFloat(now.timeIntervalSince(confirmedAt))
            let moved = y - confirmedY
            if moved < 0 || moved > lineHeight * 8 {
                // Jumped back (reset, arrow keys) or far ahead (skipped a section): start over
                speed = 0
            } else if moved > 0, elapsed > 0.05, elapsed < 4 {
                let measured = moved / elapsed
                speed = speed == 0 ? measured : speed * 0.7 + measured * 0.3
            }
            confirmedY = y
            confirmedAt = now
            leadLimit = lineHeight * 1.5
            lineStep = lineHeight
            scrollMaxY = maxY
            startTimer()
        }

        private func startTimer() {
            guard glideTimer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.step()
            }
            RunLoop.main.add(timer, forMode: .common)
            glideTimer = timer
        }

        private func step() {
            guard let scrollView else { stopTimer(); return }
            let sinceMatch = CGFloat(Date().timeIntervalSince(confirmedAt))
            let predicted = confirmedY + min(speed * sinceMatch, leadLimit)
            let target = min(max(0, predicted), scrollMaxY)
            let clip = scrollView.contentView
            let current = clip.bounds.origin.y
            let remaining = target - current
            // Ease toward the moving target, but never faster than about two lines a second,
            // so catching up after a stall glides instead of jumping. Snap when nearly there.
            let maxStep = max(lineStep * 2 / 60, speed * 1.5 / 60)
            let eased = remaining * 0.12
            let stepBy = remaining > 0 ? min(eased, maxStep) : max(eased, -maxStep * 4)
            let next = abs(remaining) < 0.3 ? target : current + stepBy
            clip.setBoundsOrigin(NSPoint(x: 0, y: next))
            scrollView.reflectScrolledClipView(clip)
            // Stop the timer once settled and no longer predicting forward movement
            if next == target && (speed == 0 || speed * sinceMatch >= leadLimit) { stopTimer() }
        }

        func stopTimer() {
            glideTimer?.invalidate()
            glideTimer = nil
        }

        deinit {
            glideTimer?.invalidate()
        }

        init(text: Binding<String>, onFocusChange: @escaping (Bool) -> Void) {
            self.textBinding = text
            self.onFocusChange = onFocusChange
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            textBinding.wrappedValue = tv.string
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused = true
            onFocusChange(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused = false
            onFocusChange(false)
        }
    }
}
