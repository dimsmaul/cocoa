import SwiftUI
import AppKit
import RichTextKit

// MARK: - CocoaRichTextView (Subclassing RichTextView from RichTextKit)
/// A zero-clutter, dark-mode native Rich Text Editor powered by RichTextKit.
/// Supports both intuitive Markdown triggers and standard Keyboard Shortcuts:
///
/// SHORTCUTS:
/// - Cmd+B: Bold
/// - Cmd+I: Italic
/// - Cmd+U: Underline
/// - Cmd+Shift+X or Cmd+Shift+S: Strikethrough
/// - Cmd+Shift+L, Cmd+L, Cmd+Shift+8, Cmd+8: Bullet List (•)
/// - Cmd+Shift+7, Cmd+7: Numbered List (1., 2., ...)
/// - Cmd+Shift+., Cmd+Shift+9, Cmd+', Cmd+Shift+Q: Blockquote (▎)
/// - Cmd+Shift+C, Cmd+E, Cmd+Shift+K: Monospace Code (chip / block)
///
/// MARKDOWN AUTO-FORMATTING ON TYPE:
/// - Type "- " or "* " at start of line -> Auto bullet list (• )
/// - Type "1. " at start of line -> Auto numbered list (1. )
/// - Type "> " at start of line -> Auto quote block (▎ )
/// - Type "`code` " -> Auto inline code chip
/// - Press Enter in list/quote -> Automatically continues to next item
/// - Press Enter on empty list/quote item -> Exits list/quote mode
/// - Press Backspace right after bullet/quote/number -> Deletes prefix in 1 keypress
@MainActor
public final class CocoaRichTextView: RichTextView {
    public var baseFontSize: CGFloat = 14
    public var onContentChange: ((NSAttributedString) -> Void)?

    private let codeBgColor = NSColor.white.withAlphaComponent(0.12)
    private let codeFgColor = NSColor(red: 1.0, green: 0.86, blue: 0.52, alpha: 1.0) // Warm amber code color
    private let quoteFgColor = NSColor(white: 0.88, alpha: 1.0)

    // Enforce white or code color for newly typed characters
    override public var typingAttributes: [NSAttributedString.Key : Any] {
        get {
            var attrs = super.typingAttributes
            if attrs[.foregroundColor] == nil {
                attrs[.foregroundColor] = NSColor.white
            }
            if attrs[.font] == nil {
                attrs[.font] = NSFont.systemFont(ofSize: baseFontSize)
            }
            return attrs
        }
        set {
            var attrs = newValue
            if attrs[.foregroundColor] == nil {
                attrs[.foregroundColor] = NSColor.white
            }
            if attrs[.font] == nil {
                attrs[.font] = NSFont.systemFont(ofSize: baseFontSize)
            }
            super.typingAttributes = attrs
        }
    }

    // MARK: - Keyboard Shortcuts Responder
    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // 1. Bold: Cmd + B
        if flags == .command && chars == "b" {
            toggleRichTextStyle(.bold)
            ensureTypingColorIsWhite()
            notifyContentChanged()
            return true
        }

        // 2. Italic: Cmd + I
        if flags == .command && chars == "i" {
            toggleRichTextStyle(.italic)
            ensureTypingColorIsWhite()
            notifyContentChanged()
            return true
        }

        // 3. Underline: Cmd + U
        if flags == .command && chars == "u" {
            toggleRichTextStyle(.underlined)
            ensureTypingColorIsWhite()
            notifyContentChanged()
            return true
        }

        // 4. Strikethrough: Cmd + Shift + X or Cmd + Shift + S
        if flags == [.command, .shift] && (chars == "x" || chars == "s") {
            toggleRichTextStyle(.strikethrough)
            ensureTypingColorIsWhite()
            notifyContentChanged()
            return true
        }

        // 5. Bullet List: Cmd + Shift + L, Cmd + L, Cmd + Shift + 8, Cmd + 8
        if ((flags == [.command, .shift] || flags == .command) && chars == "l") ||
           ((flags == [.command, .shift] || flags == .command) && (chars == "8" || chars == "*")) {
            toggleBulletList()
            return true
        }

        // 6. Numbered List: Cmd + Shift + 7, Cmd + 7
        if (flags == [.command, .shift] || flags == .command) && chars == "7" {
            toggleNumberedList()
            return true
        }

        // 7. Quote Block: Cmd + Shift + . (Cmd+>), Cmd + Shift + 9, Cmd + ', Cmd + Shift + Q
        if (flags == [.command, .shift] && (chars == "." || chars == ">" || chars == "q" || chars == "9")) ||
           (flags == .command && chars == "'") {
            toggleQuoteBlock()
            return true
        }

        // 8. Code (Inline / Block): Cmd + Shift + C, Cmd + E, Cmd + Shift + K
        if (flags == [.command, .shift] && (chars == "c" || chars == "k")) ||
           (flags == .command && chars == "e") {
            toggleCodeFormatting()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Text Input & Markdown Interception
    override public func insertText(_ string: Any, replacementRange: NSRange) {
        if let str = string as? String, str == " " {
            let range = selectedRange()
            if range.length == 0, let text = textStorage?.string as? NSString {
                let lineRange = text.lineRange(for: range)
                let linePrefix = text.substring(with: NSRange(location: lineRange.location, length: range.location - lineRange.location))

                // Markdown "- " or "* " -> Bullet list
                if linePrefix == "-" || linePrefix == "*" {
                    let replaceRange = NSRange(location: lineRange.location, length: 1)
                    if shouldChangeText(in: replaceRange, replacementString: "• ") {
                        replaceCharacters(in: replaceRange, with: "• ")
                        didChangeText()
                        setSelectedRange(NSRange(location: lineRange.location + 2, length: 0))
                        ensureTypingColorIsWhite()
                        notifyContentChanged()
                        return
                    }
                }

                // Markdown ">" -> Blockquote "▎ "
                if linePrefix == ">" {
                    let replaceRange = NSRange(location: lineRange.location, length: 1)
                    if shouldChangeText(in: replaceRange, replacementString: "▎ ") {
                        replaceCharacters(in: replaceRange, with: "▎ ")
                        didChangeText()
                        setSelectedRange(NSRange(location: lineRange.location + 2, length: 0))

                        let italicFont = NSFontManager.shared.convert(NSFont.systemFont(ofSize: baseFontSize), toHaveTrait: .italicFontMask)
                        var attrs = typingAttributes
                        attrs[.font] = italicFont
                        attrs[.foregroundColor] = quoteFgColor
                        typingAttributes = attrs

                        notifyContentChanged()
                        return
                    }
                }

                // Markdown inline code: `code` followed by Space
                if let lastTick = linePrefix.dropLast().lastIndex(of: "`"),
                   linePrefix.hasSuffix("`"),
                   lastTick < linePrefix.index(before: linePrefix.endIndex) {
                    let codeStartDist = linePrefix.distance(from: linePrefix.startIndex, to: lastTick)
                    let codeText = String(linePrefix[linePrefix.index(after: lastTick)..<linePrefix.index(before: linePrefix.endIndex)])
                    if !codeText.isEmpty && !codeText.contains(" ") {
                        let replaceRange = NSRange(location: lineRange.location + codeStartDist, length: codeText.count + 2)
                        let monoFont = NSFont.monospacedSystemFont(ofSize: baseFontSize - 0.5, weight: .medium)
                        let attrCode = NSAttributedString(string: codeText + " ", attributes: [
                            .font: monoFont,
                            .foregroundColor: codeFgColor,
                            .backgroundColor: codeBgColor
                        ])
                        if shouldChangeText(in: replaceRange, replacementString: codeText + " ") {
                            textStorage?.replaceCharacters(in: replaceRange, with: attrCode)
                            didChangeText()
                            setSelectedRange(NSRange(location: replaceRange.location + codeText.count + 1, length: 0))

                            var attrs = typingAttributes
                            attrs.removeValue(forKey: .backgroundColor)
                            attrs[.font] = NSFont.systemFont(ofSize: baseFontSize)
                            attrs[.foregroundColor] = NSColor.white
                            typingAttributes = attrs

                            notifyContentChanged()
                            return
                        }
                    }
                }
            }
        }

        super.insertText(string, replacementRange: replacementRange)
        notifyContentChanged()
    }

    // MARK: - Enter Key Interception (Auto-continue or Exit List/Quote)
    override public func insertNewline(_ sender: Any?) {
        let range = selectedRange()
        guard let text = textStorage?.string as? NSString else {
            super.insertNewline(sender)
            return
        }
        let lineRange = text.lineRange(for: NSRange(location: range.location, length: 0))
        let lineText = text.substring(with: lineRange)
        let trimmed = lineText.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Bullet list
        if trimmed == "•" {
            // Empty bullet line -> Exit bullet list
            let replaceRange = NSRange(location: lineRange.location, length: lineText.count)
            if shouldChangeText(in: replaceRange, replacementString: "") {
                replaceCharacters(in: replaceRange, with: "")
                didChangeText()
                ensureTypingColorIsWhite()
                notifyContentChanged()
                return
            }
        } else if lineText.hasPrefix("• ") {
            // Continue bullet list
            let nextBullet = "\n• "
            if shouldChangeText(in: range, replacementString: nextBullet) {
                replaceCharacters(in: range, with: nextBullet)
                didChangeText()
                setSelectedRange(NSRange(location: range.location + nextBullet.count, length: 0))
                ensureTypingColorIsWhite()
                notifyContentChanged()
                return
            }
        }

        // 2. Numbered list
        if trimmed.range(of: #"^\d+\.$"#, options: .regularExpression) != nil {
            // Empty numbered line -> Exit numbered list
            let replaceRange = NSRange(location: lineRange.location, length: lineText.count)
            if shouldChangeText(in: replaceRange, replacementString: "") {
                replaceCharacters(in: replaceRange, with: "")
                didChangeText()
                ensureTypingColorIsWhite()
                notifyContentChanged()
                return
            }
        } else if let numRange = trimmed.range(of: #"^(\d+)\.\s+"#, options: .regularExpression) {
            let numStr = String(trimmed[numRange]).trimmingCharacters(in: .whitespaces).dropLast()
            if let currentNum = Int(numStr) {
                let nextNumStr = "\n\(currentNum + 1). "
                if shouldChangeText(in: range, replacementString: nextNumStr) {
                    replaceCharacters(in: range, with: nextNumStr)
                    didChangeText()
                    setSelectedRange(NSRange(location: range.location + nextNumStr.count, length: 0))
                    ensureTypingColorIsWhite()
                    notifyContentChanged()
                    return
                }
            }
        }

        // 3. Blockquote
        if trimmed == "▎" {
            // Empty quote line -> Exit quote
            let replaceRange = NSRange(location: lineRange.location, length: lineText.count)
            if shouldChangeText(in: replaceRange, replacementString: "") {
                replaceCharacters(in: replaceRange, with: "")
                didChangeText()
                ensureTypingColorIsWhite()
                notifyContentChanged()
                return
            }
        } else if lineText.hasPrefix("▎ ") {
            let nextQuote = "\n▎ "
            if shouldChangeText(in: range, replacementString: nextQuote) {
                replaceCharacters(in: range, with: nextQuote)
                didChangeText()
                setSelectedRange(NSRange(location: range.location + nextQuote.count, length: 0))
                ensureTypingColorIsWhite()
                notifyContentChanged()
                return
            }
        }

        // Standard newline
        super.insertNewline(sender)

        var attrs = typingAttributes
        attrs.removeValue(forKey: .backgroundColor)
        attrs[.font] = NSFont.systemFont(ofSize: baseFontSize)
        attrs[.foregroundColor] = NSColor.white
        typingAttributes = attrs

        notifyContentChanged()
    }

    // MARK: - Backspace Key Interception (One-touch delete of prefix)
    override public func deleteBackward(_ sender: Any?) {
        let range = selectedRange()
        if range.length == 0, let text = textStorage?.string as? NSString {
            let lineRange = text.lineRange(for: range)
            let lineText = text.substring(with: NSRange(location: lineRange.location, length: range.location - lineRange.location))

            if lineText == "• " || lineText == "▎ " {
                let deleteRange = NSRange(location: lineRange.location, length: 2)
                if shouldChangeText(in: deleteRange, replacementString: "") {
                    replaceCharacters(in: deleteRange, with: "")
                    didChangeText()
                    setSelectedRange(NSRange(location: lineRange.location, length: 0))
                    ensureTypingColorIsWhite()
                    notifyContentChanged()
                    return
                }
            }

            if let match = lineText.range(of: #"^\d+\.\s$"#, options: .regularExpression) {
                let matchLen = lineText.distance(from: match.lowerBound, to: match.upperBound)
                let deleteRange = NSRange(location: lineRange.location, length: matchLen)
                if shouldChangeText(in: deleteRange, replacementString: "") {
                    replaceCharacters(in: deleteRange, with: "")
                    didChangeText()
                    setSelectedRange(NSRange(location: lineRange.location, length: 0))
                    ensureTypingColorIsWhite()
                    notifyContentChanged()
                    return
                }
            }
        }

        super.deleteBackward(sender)
        notifyContentChanged()
    }

    // MARK: - Rich Feature Toggles

    /// Toggles Bullet List (•) on the current line or selection
    public func toggleBulletList() {
        let range = selectedRange()
        guard let text = textStorage?.string as? NSString else { return }
        let lineRange = text.lineRange(for: range)
        let fullLine = text.substring(with: lineRange)

        let lines = fullLine.components(separatedBy: "\n")
        var newLines: [String] = []

        let allHaveBullet = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("• ") }

        for line in lines {
            if line.isEmpty && lines.count > 1 {
                newLines.append(line)
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if allHaveBullet {
                if trimmed.hasPrefix("• ") {
                    newLines.append(String(trimmed.dropFirst(2)))
                } else {
                    newLines.append(line)
                }
            } else {
                var clean = trimmed
                if clean.hasPrefix("▎ ") { clean = String(clean.dropFirst(2)) }
                if let numMatch = clean.range(of: #"^\d+\.\s*"#, options: .regularExpression) {
                    clean.removeSubrange(numMatch)
                }
                newLines.append("• " + clean)
            }
        }

        let replacement = newLines.joined(separator: "\n")
        if shouldChangeText(in: lineRange, replacementString: replacement) {
            replaceCharacters(in: lineRange, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location + replacement.count, length: 0))
            ensureTypingColorIsWhite()
            notifyContentChanged()
        }
    }

    /// Toggles Numbered List (1., 2., ...) on current line or selection
    public func toggleNumberedList() {
        let range = selectedRange()
        guard let text = textStorage?.string as? NSString else { return }
        let lineRange = text.lineRange(for: range)
        let fullLine = text.substring(with: lineRange)

        let lines = fullLine.components(separatedBy: "\n")
        var newLines: [String] = []
        var counter = 1

        let allHaveNumber = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .allSatisfy { $0.trimmingCharacters(in: .whitespaces).range(of: #"^\d+\.\s*"#, options: .regularExpression) != nil }

        for line in lines {
            if line.isEmpty && lines.count > 1 {
                newLines.append(line)
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if allHaveNumber {
                if let match = trimmed.range(of: #"^\d+\.\s*"#, options: .regularExpression) {
                    var clean = trimmed
                    clean.removeSubrange(match)
                    newLines.append(clean)
                } else {
                    newLines.append(line)
                }
            } else {
                var clean = trimmed
                if clean.hasPrefix("• ") { clean = String(clean.dropFirst(2)) }
                if clean.hasPrefix("▎ ") { clean = String(clean.dropFirst(2)) }
                if let match = clean.range(of: #"^\d+\.\s*"#, options: .regularExpression) {
                    clean.removeSubrange(match)
                }
                newLines.append("\(counter). " + clean)
                counter += 1
            }
        }

        let replacement = newLines.joined(separator: "\n")
        if shouldChangeText(in: lineRange, replacementString: replacement) {
            replaceCharacters(in: lineRange, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location + replacement.count, length: 0))
            ensureTypingColorIsWhite()
            notifyContentChanged()
        }
    }

    /// Toggles Blockquote (▎) on current line or selection
    public func toggleQuoteBlock() {
        let range = selectedRange()
        guard let text = textStorage?.string as? NSString else { return }
        let lineRange = text.lineRange(for: range)
        let fullLine = text.substring(with: lineRange)

        let lines = fullLine.components(separatedBy: "\n")
        var newLines: [String] = []

        let allHaveQuote = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("▎ ") }

        for line in lines {
            if line.isEmpty && lines.count > 1 {
                newLines.append(line)
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if allHaveQuote {
                if trimmed.hasPrefix("▎ ") {
                    newLines.append(String(trimmed.dropFirst(2)))
                } else {
                    newLines.append(line)
                }
            } else {
                var clean = trimmed
                if clean.hasPrefix("• ") { clean = String(clean.dropFirst(2)) }
                if let match = clean.range(of: #"^\d+\.\s*"#, options: .regularExpression) {
                    clean.removeSubrange(match)
                }
                newLines.append("▎ " + clean)
            }
        }

        let replacement = newLines.joined(separator: "\n")
        if shouldChangeText(in: lineRange, replacementString: replacement) {
            replaceCharacters(in: lineRange, with: replacement)
            didChangeText()

            let updatedRange = NSRange(location: lineRange.location, length: replacement.count)
            if !allHaveQuote {
                let italicFont = NSFontManager.shared.convert(NSFont.systemFont(ofSize: baseFontSize), toHaveTrait: .italicFontMask)
                textStorage?.addAttribute(.font, value: italicFont, range: updatedRange)
                textStorage?.addAttribute(.foregroundColor, value: quoteFgColor, range: updatedRange)
            } else {
                textStorage?.addAttribute(.font, value: NSFont.systemFont(ofSize: baseFontSize), range: updatedRange)
                textStorage?.addAttribute(.foregroundColor, value: NSColor.white, range: updatedRange)
            }

            setSelectedRange(NSRange(location: lineRange.location + replacement.count, length: 0))
            ensureTypingColorIsWhite()
            notifyContentChanged()
        }
    }

    /// Toggles Monospaced Code formatting (amber text on subtle rounded background)
    public func toggleCodeFormatting() {
        let range = selectedRange()
        let monoFont = NSFont.monospacedSystemFont(ofSize: baseFontSize - 0.5, weight: .medium)

        if range.length > 0 {
            guard let storage = textStorage else { return }

            var isCode = false
            storage.enumerateAttribute(.font, in: range) { val, _, stop in
                if let font = val as? NSFont, self.isMonoFont(font) {
                    isCode = true
                    stop.pointee = true
                }
            }

            if isCode {
                storage.removeAttribute(.backgroundColor, range: range)
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: baseFontSize), range: range)
                storage.addAttribute(.foregroundColor, value: NSColor.white, range: range)
            } else {
                storage.addAttribute(.backgroundColor, value: codeBgColor, range: range)
                storage.addAttribute(.font, value: monoFont, range: range)
                storage.addAttribute(.foregroundColor, value: codeFgColor, range: range)
            }
            didChangeText()
            notifyContentChanged()
        } else {
            var attrs = typingAttributes
            if let currentFont = attrs[.font] as? NSFont, isMonoFont(currentFont) {
                attrs.removeValue(forKey: .backgroundColor)
                attrs[.font] = NSFont.systemFont(ofSize: baseFontSize)
                attrs[.foregroundColor] = NSColor.white
            } else {
                attrs[.backgroundColor] = codeBgColor
                attrs[.font] = monoFont
                attrs[.foregroundColor] = codeFgColor
            }
            typingAttributes = attrs
        }
    }

    private func isMonoFont(_ font: NSFont) -> Bool {
        let name = font.fontName.lowercased()
        return font.isFixedPitch || name.contains("mono") || name.contains("menlo") || name.contains("courier")
    }

    public func ensureTypingColorIsWhite() {
        var attrs = typingAttributes
        if attrs[.backgroundColor] == nil {
            attrs[.foregroundColor] = NSColor.white
        }
        typingAttributes = attrs
    }

    public func notifyContentChanged() {
        if let storage = textStorage {
            onContentChange?(storage)
        }
    }
}

// MARK: - NativeRichTextEditor (SwiftUI Representable)
public struct NativeRichTextEditor: View {
    @Binding public var text: String
    public var baseFontSize: CGFloat
    public var minHeight: CGFloat

    public init(text: Binding<String>, baseFontSize: CGFloat = 14, minHeight: CGFloat = 100) {
        self._text = text
        self.baseFontSize = baseFontSize
        self.minHeight = minHeight
    }

    public var body: some View {
        RichTextRepresentable(text: $text, baseFontSize: baseFontSize)
            .frame(minHeight: minHeight)
            .padding(8)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
            )
    }
}

// MARK: - NSViewRepresentable Wrapper
@MainActor
private struct RichTextRepresentable: NSViewRepresentable {
    @Binding var text: String
    var baseFontSize: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = CocoaRichTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.baseFontSize = baseFontSize
        textView.appearance = NSAppearance(named: .darkAqua)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.drawsBackground = false
        textView.textColor = NSColor.white
        textView.insertionPointColor = NSColor.white
        textView.font = NSFont.systemFont(ofSize: baseFontSize)
        textView.allowsUndo = true
        textView.isRichText = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        // Populate initial text
        context.coordinator.loadTextIntoView(text)

        textView.onContentChange = { attributed in
            context.coordinator.syncToBinding(attributed)
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CocoaRichTextView else { return }
        textView.baseFontSize = baseFontSize

        if !context.coordinator.isInternalUpdate && context.coordinator.lastSyncedText != text {
            context.coordinator.loadTextIntoView(text)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextRepresentable
        weak var textView: CocoaRichTextView?
        var lastSyncedText: String = ""
        var isInternalUpdate = false

        init(_ parent: RichTextRepresentable) {
            self.parent = parent
        }

        func loadTextIntoView(_ string: String) {
            guard let textView = textView else { return }
            isInternalUpdate = true
            defer { isInternalUpdate = false }

            lastSyncedText = string
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("{\\rtf") || trimmed.hasPrefix("{\\urtf"),
               let data = string.data(using: .utf8),
               let attr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                let sanitized = sanitize(attr, baseFontSize: parent.baseFontSize)
                textView.textStorage?.setAttributedString(sanitized)
            } else {
                let attr = NSMutableAttributedString(string: string, attributes: [
                    .font: NSFont.systemFont(ofSize: parent.baseFontSize),
                    .foregroundColor: NSColor.white
                ])
                textView.textStorage?.setAttributedString(attr)
            }

            textView.ensureTypingColorIsWhite()
        }

        func textDidChange(_ notification: Notification) {
            guard !isInternalUpdate, let textView = textView else { return }
            textView.ensureTypingColorIsWhite()
            if let storage = textView.textStorage {
                syncToBinding(storage)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = textView else { return }
            textView.ensureTypingColorIsWhite()
        }

        func syncToBinding(_ attr: NSAttributedString) {
            guard !isInternalUpdate else { return }
            isInternalUpdate = true
            defer { isInternalUpdate = false }

            let sanitized = sanitize(attr, baseFontSize: parent.baseFontSize)

            // If text contains rich attributes (bold, italic, underline, strikethrough, code, or background), serialize to RTF
            if hasRichFormatting(sanitized),
               let data = try? sanitized.richTextData(for: .rtf),
               let rtfString = String(data: data, encoding: .utf8) {
                lastSyncedText = rtfString
                parent.text = rtfString
            } else {
                let plain = sanitized.string
                lastSyncedText = plain
                parent.text = plain
            }
        }

        private func hasRichFormatting(_ attr: NSAttributedString) -> Bool {
            var hasRich = false
            let fullRange = NSRange(location: 0, length: attr.length)
            attr.enumerateAttributes(in: fullRange) { attrs, _, stop in
                if attrs[.underlineStyle] != nil ||
                   attrs[.strikethroughStyle] != nil ||
                   attrs[.backgroundColor] != nil {
                    hasRich = true
                    stop.pointee = true
                    return
                }
                if let font = attrs[.font] as? NSFont {
                    let name = font.fontName.lowercased()
                    if font.isFixedPitch || name.contains("mono") || name.contains("menlo") || name.contains("courier") {
                        hasRich = true
                        stop.pointee = true
                        return
                    }
                    let traits = NSFontManager.shared.traits(of: font)
                    if traits.contains(.boldFontMask) || traits.contains(.italicFontMask) {
                        hasRich = true
                        stop.pointee = true
                        return
                    }
                }
            }
            return hasRich
        }

        private func sanitize(_ attr: NSAttributedString, baseFontSize: CGFloat) -> NSAttributedString {
            let mutable = NSMutableAttributedString(attributedString: attr)
            let fullRange = NSRange(location: 0, length: mutable.length)
            guard fullRange.length > 0 else { return attr }

            // 1. Force white color for all characters that are black, dark, or unassigned (preserving warm code colors)
            mutable.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
                if let color = value as? NSColor {
                    if isDarkColor(color) {
                        mutable.addAttribute(.foregroundColor, value: NSColor.white, range: range)
                    }
                } else {
                    mutable.addAttribute(.foregroundColor, value: NSColor.white, range: range)
                }
            }

            // 2. Ensure font has at least baseFontSize while preserving monospace, bold, italic traits
            mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
                if let font = value as? NSFont {
                    let targetSize = max(baseFontSize, font.pointSize)
                    let name = font.fontName.lowercased()
                    let isMono = font.isFixedPitch || name.contains("mono") || name.contains("menlo") || name.contains("courier")

                    if isMono {
                        let newFont = NSFont.monospacedSystemFont(ofSize: targetSize - 0.5, weight: .medium)
                        mutable.addAttribute(.font, value: newFont, range: range)
                    } else {
                        let traits = NSFontManager.shared.traits(of: font)
                        var newFont = NSFont.systemFont(ofSize: targetSize)
                        if traits.contains(.boldFontMask) && traits.contains(.italicFontMask) {
                            newFont = NSFontManager.shared.convert(newFont, toHaveTrait: [.boldFontMask, .italicFontMask])
                        } else if traits.contains(.boldFontMask) {
                            newFont = NSFontManager.shared.convert(newFont, toHaveTrait: .boldFontMask)
                        } else if traits.contains(.italicFontMask) {
                            newFont = NSFontManager.shared.convert(newFont, toHaveTrait: .italicFontMask)
                        }
                        mutable.addAttribute(.font, value: newFont, range: range)
                    }
                } else {
                    mutable.addAttribute(.font, value: NSFont.systemFont(ofSize: baseFontSize), range: range)
                }
            }

            return mutable
        }

        private func isDarkColor(_ color: NSColor) -> Bool {
            guard let rgb = color.usingColorSpace(.sRGB) else { return false }
            return rgb.redComponent < 0.45 && rgb.greenComponent < 0.45 && rgb.blueComponent < 0.45
        }
    }
}

// MARK: - Native Rich Text Viewer (Displays formatted RTF with zero options)
public struct NativeRichTextViewer: View {
    public let text: String
    public var baseFontSize: CGFloat
    public var textColor: Color

    public init(text: String, baseFontSize: CGFloat = 14, textColor: Color = .white) {
        self.text = text
        self.baseFontSize = baseFontSize
        self.textColor = textColor
    }

    public var body: some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if (trimmed.hasPrefix("{\\rtf") || trimmed.hasPrefix("{\\urtf")),
           let data = text.data(using: .utf8),
           let attr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            let sanitized = sanitizeAttributed(attr)
            RichTextViewer(sanitized)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !trimmed.isEmpty {
            Text(LocalizedStringKey(text))
                .font(.system(size: baseFontSize))
                .lineSpacing(4)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("No notes attached.")
                .font(.system(size: baseFontSize))
                .foregroundStyle(textColor.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sanitizeAttributed(_ attr: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attr)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.foregroundColor, in: fullRange) { val, range, _ in
            if let c = val as? NSColor {
                if isDarkColor(c) {
                    mutable.addAttribute(.foregroundColor, value: NSColor.white, range: range)
                }
            } else {
                mutable.addAttribute(.foregroundColor, value: NSColor.white, range: range)
            }
        }
        return mutable
    }

    private func isDarkColor(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return false }
        return rgb.redComponent < 0.45 && rgb.greenComponent < 0.45 && rgb.blueComponent < 0.45
    }
}
