import AppKit
import CoreText
import SwiftUI

// The editor keeps plain Markdown in its text storage and only changes how it looks, so what
// you type, what is saved, and what an agent reads or writes are the same string.

private extension NSAttributedString.Key {
    static let markdownHidden = NSAttributedString.Key("cocoa.markdownHidden")
    static let markdownBullet = NSAttributedString.Key("cocoa.markdownBullet")
    static let markdownBlock = NSAttributedString.Key("cocoa.markdownBlock")
    static let markdownTaskBox = NSAttributedString.Key("cocoa.markdownTaskBox")
}

private enum MarkdownBlock: String {
    case code, quote, rule
}

private enum MarkdownTheme {
    static let text = NSColor.white
    static let secondary = NSColor.white.withAlphaComponent(0.62)
    static let dimmed = NSColor.white.withAlphaComponent(0.35)
    static let accent = NSColor.systemOrange
    static let code = NSColor(red: 1.0, green: 0.86, blue: 0.52, alpha: 1.0)
    static let codeBackground = NSColor.white.withAlphaComponent(0.12)
    static let blockBackground = NSColor.white.withAlphaComponent(0.06)
    static let link = NSColor(red: 0.45, green: 0.72, blue: 1.0, alpha: 1.0)
    static let done = NSColor.systemGreen
}

// MARK: - Styling

@MainActor
enum MarkdownStyler {
    static func baseAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: MarkdownTheme.text,
            .paragraphStyle: paragraph()
        ]
    }

    /// ponytail: restyles the whole note on each change, fine for notes of a few pages; style only the edited lines if long notes lag.
    static func apply(to storage: NSTextStorage, fontSize: CGFloat, revealedLine: NSRange?) {
        let full = NSRange(location: 0, length: storage.length)
        let spans = MarkdownParser.spans(in: storage.string)

        storage.beginEditing()
        storage.setAttributes(baseAttributes(fontSize: fontSize), range: full)
        spans.forEach { applyBlock($0, to: storage, fontSize: fontSize, revealedLine: revealedLine) }
        spans.forEach { applyInline($0, to: storage, fontSize: fontSize, revealedLine: revealedLine) }
        storage.endEditing()

        // Hidden characters are decided when glyphs are generated, which attribute changes do not redo.
        storage.layoutManagers.forEach {
            $0.invalidateGlyphs(forCharacterRange: full, changeInLength: 0, actualCharacterRange: nil)
        }
    }

    private static func paragraph(
        indent: CGFloat = 0,
        headIndent: CGFloat? = nil,
        before: CGFloat = 0,
        after: CGFloat = 3,
        lineSpacing: CGFloat = 2
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent
        style.headIndent = headIndent ?? indent
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.lineSpacing = lineSpacing
        return style
    }

    private static func isRevealed(_ range: NSRange, _ revealedLine: NSRange?) -> Bool {
        guard let revealedLine else { return false }
        return NSLocationInRange(range.location, revealedLine)
            || (range.location == NSMaxRange(revealedLine) && revealedLine.length == 0)
    }

    private static func monoFont(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    private static func characterWidth(of font: NSFont) -> CGFloat {
        ("0" as NSString).size(withAttributes: [.font: font]).width
    }

    private static func applyBlock(_ span: MarkdownSpan, to storage: NSTextStorage, fontSize: CGFloat, revealedLine: NSRange?) {
        let range = span.range
        let mono = monoFont(fontSize - 0.5)

        switch span.kind {
        case .heading(let level):
            let increase: [CGFloat] = [9, 6, 3, 1, 0, 0]
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize + increase[min(level, 6) - 1], weight: .bold), range: range)
            storage.addAttribute(.paragraphStyle, value: paragraph(before: 6, after: 4), range: range)

        case .listItem(let indent):
            storage.addAttribute(.paragraphStyle, value: paragraph(headIndent: CGFloat(indent) * characterWidth(of: mono)), range: range)

        case .quote:
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.secondary, range: range)
            storage.addAttribute(.paragraphStyle, value: paragraph(indent: 12), range: range)
            storage.addAttribute(.markdownBlock, value: MarkdownBlock.quote.rawValue, range: range)

        case .codeBlock, .codeFence:
            let isFence = span.kind == .codeFence
            storage.addAttribute(.font, value: mono, range: range)
            storage.addAttribute(.foregroundColor, value: isFence ? MarkdownTheme.dimmed : MarkdownTheme.code, range: range)
            storage.addAttribute(.paragraphStyle, value: paragraph(indent: 8, after: 0, lineSpacing: 1), range: range)
            storage.addAttribute(.markdownBlock, value: MarkdownBlock.code.rawValue, range: range)

        case .tableRow(let isHeader):
            storage.addAttribute(.font, value: monoFont(fontSize - 0.5, weight: isHeader ? .bold : .regular), range: range)

        case .tableDivider:
            if isRevealed(range, revealedLine) {
                storage.addAttribute(.font, value: mono, range: range)
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimmed, range: range)
            } else {
                // Collapsed to a thin gap under the header.
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 2), range: range)
                storage.addAttribute(.markdownHidden, value: true, range: range)
                storage.addAttribute(.paragraphStyle, value: paragraph(after: 0, lineSpacing: 0), range: range)
            }

        case .horizontalRule:
            storage.addAttribute(.markdownBlock, value: MarkdownBlock.rule.rawValue, range: range)
            if isRevealed(range, revealedLine) {
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimmed, range: range)
            } else {
                storage.addAttribute(.markdownHidden, value: true, range: range)
            }

        default:
            break
        }
    }

    private static func applyInline(_ span: MarkdownSpan, to storage: NSTextStorage, fontSize: CGFloat, revealedLine: NSRange?) {
        let range = span.range

        switch span.kind {
        case .bold:
            applyTrait(.boldFontMask, to: storage, range: range)

        case .italic:
            applyTrait(.italicFontMask, to: storage, range: range)

        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)

        case .inlineCode:
            let current = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            // Text that is already monospaced, like a table cell, keeps its size so columns stay aligned.
            let size = current.map { $0.isFixedPitch ? $0.pointSize : $0.pointSize - 0.5 } ?? fontSize - 0.5
            storage.addAttribute(.font, value: monoFont(size, weight: .medium), range: range)
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.code, range: range)
            storage.addAttribute(.backgroundColor, value: MarkdownTheme.codeBackground, range: range)

        case .link(let address):
            if let url = URL(string: address) {
                storage.addAttribute(.link, value: url, range: range)
            }
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.link, range: range)

        case .marker:
            if isRevealed(range, revealedLine) {
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimmed, range: range)
            } else {
                // Tiny rather than a null glyph: a null glyph at the start of a line stops it
                // counting as a paragraph start, which breaks indents and block backgrounds.
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.01), range: range)
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
            }

        case .listMarker:
            storage.addAttribute(.markdownBullet, value: true, range: range)
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.accent, range: range)

        case .orderedMarker:
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.accent, range: range)

        case .taskBox(let isChecked):
            storage.addAttribute(.font, value: monoFont(fontSize - 0.5, weight: .bold), range: range)
            storage.addAttribute(.foregroundColor, value: isChecked ? MarkdownTheme.done : MarkdownTheme.accent, range: range)
            storage.addAttribute(.markdownTaskBox, value: true, range: range)

        case .completedTask:
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.secondary, range: range)
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)

        case .tablePipe:
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimmed, range: range)

        case .tablePadding(let columns):
            let mono = monoFont(fontSize - 0.5)
            storage.addAttribute(.kern, value: CGFloat(columns) * characterWidth(of: mono), range: range)

        default:
            break
        }
    }

    private static func applyTrait(_ trait: NSFontTraitMask, to storage: NSTextStorage, range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: subrange)
        }
    }
}

// MARK: - Layout: hidden syntax, bullets, and full-width block backgrounds

private final class MarkdownLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let storage = textStorage else { return 0 }

        var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
        var newProperties = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
        var isChanged = false

        for index in 0..<glyphRange.length {
            let character = characterIndexes[index]
            guard character < storage.length else { continue }
            if storage.attribute(.markdownHidden, at: character, effectiveRange: nil) != nil {
                newProperties[index] = .null
                isChanged = true
            } else if storage.attribute(.markdownBullet, at: character, effectiveRange: nil) != nil {
                var bullet: UniChar = 0x2022
                var glyph: CGGlyph = 0
                if CTFontGetGlyphsForCharacters(font as CTFont, &bullet, &glyph, 1) {
                    newGlyphs[index] = glyph
                    isChanged = true
                }
            }
        }

        guard isChanged else { return 0 }
        setGlyphs(newGlyphs, properties: newProperties, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }

        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.markdownBlock, in: characters) { value, range, _ in
            guard let raw = value as? String, let block = MarkdownBlock(rawValue: raw) else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                let line = rect.offsetBy(dx: origin.x, dy: origin.y)
                switch block {
                case .code:
                    MarkdownTheme.blockBackground.setFill()
                    line.fill()
                case .quote:
                    MarkdownTheme.accent.withAlphaComponent(0.7).setFill()
                    NSRect(x: line.minX + 1, y: line.minY, width: 3, height: line.height).fill()
                case .rule:
                    NSColor.white.withAlphaComponent(0.2).setFill()
                    NSRect(x: line.minX, y: line.midY, width: line.width, height: 1).fill()
                }
            }
        }
    }
}

// MARK: - Text View

@MainActor
final class MarkdownTextView: NSTextView {
    var baseFontSize: CGFloat = 14
    private var revealedLine: NSRange?
    private var isRestyling = false

    /// Builds the text system with the layout manager that hides Markdown syntax.
    static func make(fontSize: CGFloat, frame: NSRect = .zero) -> MarkdownTextView {
        let storage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(containerSize: NSSize(width: frame.width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let view = MarkdownTextView(frame: frame, textContainer: container)
        view.baseFontSize = fontSize
        view.appearance = NSAppearance(named: .darkAqua)
        view.minSize = NSSize(width: 0, height: frame.height)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainerInset = NSSize(width: 4, height: 4)
        view.drawsBackground = false
        view.insertionPointColor = .white
        view.allowsUndo = true
        view.isRichText = false
        view.importsGraphics = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.linkTextAttributes = [.foregroundColor: MarkdownTheme.link, .underlineStyle: NSUnderlineStyle.single.rawValue, .cursor: NSCursor.pointingHand]
        view.typingAttributes = MarkdownStyler.baseAttributes(fontSize: fontSize)
        return view
    }

    func setMarkdown(_ markdown: String) {
        let selection = selectedRange()
        string = markdown
        undoManager?.removeAllActions()
        let length = (markdown as NSString).length
        let location = min(selection.location, length)
        setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
        restyle()
    }

    func restyle() {
        guard let storage = textStorage, !isRestyling, !hasMarkedText() else { return }
        isRestyling = true
        defer { isRestyling = false }
        revealedLine = currentLine()
        MarkdownStyler.apply(to: storage, fontSize: baseFontSize, revealedLine: revealedLine)
        typingAttributes = MarkdownStyler.baseAttributes(fontSize: baseFontSize)
    }

    /// Syntax appears only on the line being edited, so restyle when the caret changes line.
    func caretMoved() {
        if currentLine() != revealedLine {
            restyle()
        }
    }

    private func currentLine() -> NSRange? {
        guard window?.firstResponder === self else { return nil }
        return (string as NSString).lineRange(for: selectedRange())
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { DispatchQueue.main.async { [weak self] in self?.restyle() } }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { DispatchQueue.main.async { [weak self] in self?.restyle() } }
        return accepted
    }

    // MARK: Commands

    func apply(_ edit: MarkdownEdit) {
        let full = NSRange(location: 0, length: (string as NSString).length)
        guard shouldChangeText(in: full, replacementString: edit.text) else { return }
        replaceCharacters(in: full, with: edit.text)
        setSelectedRange(edit.selection)
        didChangeText()
    }

    func toggleWrap(_ marker: String) {
        apply(MarkdownEditing.toggleWrap(text: string, selection: selectedRange(), marker: marker))
    }

    func toggleLine(_ style: MarkdownLineStyle) {
        apply(MarkdownEditing.togglePrefix(text: string, selection: selectedRange(), style: style))
    }

    func insertLink() {
        apply(MarkdownEditing.insertLink(text: string, selection: selectedRange()))
    }

    func insertCodeBlock() {
        apply(MarkdownEditing.insertCodeBlock(text: string, selection: selectedRange()))
    }

    // MARK: Shortcuts

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Key equivalents reach every view in the window, focused or not.
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }

        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let command: NSEvent.ModifierFlags = .command
        let commandShift: NSEvent.ModifierFlags = [.command, .shift]
        let commandOption: NSEvent.ModifierFlags = [.command, .option]
        let isCommandOrShift = flags == command || flags == commandShift

        switch true {
        case flags == command && key == "b": toggleWrap("**")
        case flags == command && key == "i": toggleWrap("*")
        case flags == commandShift && (key == "x" || key == "s"): toggleWrap("~~")
        case isCommandOrShift && (key == "l" || key == "8" || key == "*"): toggleLine(.bullet)
        case isCommandOrShift && key == "7": toggleLine(.numbered)
        case flags == commandShift && key == "t": toggleLine(.task)
        case (flags == commandShift && (key == "." || key == ">" || key == "q" || key == "9")) || (flags == command && key == "'"):
            toggleLine(.quote)
        case (flags == commandShift && (key == "c" || key == "k")) || (flags == command && key == "e"):
            toggleWrap("`")
        case flags == commandShift && key == "e": insertCodeBlock()
        case flags == command && key == "k": insertLink()
        case flags == commandOption && key == "1": toggleLine(.heading(1))
        case flags == commandOption && key == "2": toggleLine(.heading(2))
        case flags == commandOption && key == "3": toggleLine(.heading(3))
        default:
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // MARK: Typing

    private var isCaretInCode: Bool {
        let location = selectedRange().location
        return MarkdownParser.spans(in: string).contains {
            ($0.kind == .codeBlock || $0.kind == .codeFence) && location >= $0.range.location && location <= NSMaxRange($0.range)
        }
    }

    /// Space after `[]` or `[x]` turns the line into a checkbox.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let source = self.string as NSString
        let selection = selectedRange()
        if string as? String == " ", replacementRange.location == NSNotFound, selection.length == 0, !isCaretInCode {
            let line = source.lineRange(for: selection)
            let typed = NSRange(location: line.location, length: selection.location - line.location)
            if let formatted = MarkdownEditing.autoFormat(beforeCaret: source.substring(with: typed)) {
                super.insertText(formatted, replacementRange: typed)
                return
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func insertNewline(_ sender: Any?) {
        let source = string as NSString
        let selection = selectedRange()
        let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let text = source.substring(with: line).trimmingCharacters(in: .newlines)

        if selection.length == 0, let closed = MarkdownEditing.autoCloseFence(text: string, caret: selection.location) {
            apply(closed)
            return
        }

        guard selection.length == 0, !isCaretInCode else {
            super.insertNewline(sender)
            return
        }

        switch MarkdownEditing.newlineAction(forLine: text) {
        case .none:
            super.insertNewline(sender)
        case .insert(let continuation):
            insertText(continuation, replacementRange: selection)
        case .exitBlock:
            let content = NSRange(location: line.location, length: (text as NSString).length)
            insertText("", replacementRange: content)
        }
    }

    /// Backspace right after an empty list or quote marker removes the whole marker.
    override func deleteBackward(_ sender: Any?) {
        let source = string as NSString
        let selection = selectedRange()
        if selection.length == 0 {
            let line = source.lineRange(for: selection)
            let before = source.substring(with: NSRange(location: line.location, length: selection.location - line.location))
            if !before.isEmpty, MarkdownEditing.newlineAction(forLine: before) == .exitBlock, !isCaretInCode {
                insertText("", replacementRange: NSRange(location: line.location, length: selection.location - line.location))
                return
            }
        }
        super.deleteBackward(sender)
    }

    /// Tab indents a list item to nest it. Everywhere else it types a tab.
    override func insertTab(_ sender: Any?) {
        let source = string as NSString
        let line = source.lineRange(for: selectedRange())
        let text = source.substring(with: line).trimmingCharacters(in: .newlines)
        if case .insert = MarkdownEditing.newlineAction(forLine: text), !isCaretInCode {
            insertText("  ", replacementRange: NSRange(location: line.location, length: 0))
        } else if MarkdownEditing.newlineAction(forLine: text) == .exitBlock, !isCaretInCode {
            insertText("  ", replacementRange: NSRange(location: line.location, length: 0))
        } else {
            super.insertTab(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        let source = string as NSString
        let line = source.lineRange(for: selectedRange())
        if line.length >= 2, source.substring(with: NSRange(location: line.location, length: 2)) == "  " {
            insertText("", replacementRange: NSRange(location: line.location, length: 2))
        } else {
            super.insertBacktab(sender)
        }
    }

    // MARK: Checklists

    override func mouseDown(with event: NSEvent) {
        if let box = taskBox(at: convert(event.locationInWindow, from: nil)) {
            let source = string as NSString
            let isChecked = source.substring(with: box).lowercased() == "[x]"
            let inner = NSRange(location: box.location + 1, length: 1)
            let replacement = isChecked ? " " : "x"
            if shouldChangeText(in: inner, replacementString: replacement) {
                replaceCharacters(in: inner, with: replacement)
                didChangeText()
            }
            return
        }
        super.mouseDown(with: event)
    }

    private func taskBox(at point: NSPoint) -> NSRange? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let index = characterIndexForInsertion(at: point)
        for candidate in [index, index - 1] where candidate >= 0 && candidate < storage.length {
            var range = NSRange()
            if storage.attribute(.markdownTaskBox, at: candidate, effectiveRange: &range) != nil {
                return range
            }
        }
        return nil
    }
}

// MARK: - SwiftUI Editor

public struct NativeRichTextEditor: View {
    @Binding public var text: String
    public var taskId: UUID?
    public var baseFontSize: CGFloat
    public var minHeight: CGFloat
    /// Grows to fit the note and lets the surrounding scroll view do the scrolling.
    public var growsWithContent: Bool

    @State private var contentHeight: CGFloat = 0

    public init(
        text: Binding<String>,
        taskId: UUID? = nil,
        baseFontSize: CGFloat = 14,
        minHeight: CGFloat = 100,
        growsWithContent: Bool = false
    ) {
        self._text = text
        self.taskId = taskId
        self.baseFontSize = baseFontSize
        self.minHeight = minHeight
        self.growsWithContent = growsWithContent
    }

    public var body: some View {
        MarkdownEditorRepresentable(
            text: $text,
            taskId: taskId,
            baseFontSize: baseFontSize,
            growsWithContent: growsWithContent,
            onContentHeightChange: { contentHeight = $0 }
        )
        .frame(
            minHeight: minHeight,
            idealHeight: growsWithContent ? max(minHeight, contentHeight) : nil,
            maxHeight: growsWithContent ? max(minHeight, contentHeight) : .infinity
        )
        .padding(8)
        .overlay(alignment: .topLeading) {
            if text.isEmpty {
                Text("Write in Markdown")
                    .font(.system(size: baseFontSize))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
        )
    }
}

// MARK: - NSViewRepresentable Wrapper

/// Hands wheel events to the surrounding scroll view when the editor grows to fit its content.
private final class PassthroughScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

@MainActor
private struct MarkdownEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    var taskId: UUID?
    var baseFontSize: CGFloat
    var growsWithContent: Bool
    var onContentHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = growsWithContent ? PassthroughScrollView() : NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = !growsWithContent
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = MarkdownTextView.make(fontSize: baseFontSize, frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.delegate = context.coordinator
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.currentTaskId = taskId
        context.coordinator.load(text)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.textView?.baseFontSize = baseFontSize

        if let taskId, coordinator.currentTaskId != taskId {
            coordinator.currentTaskId = taskId
            coordinator.textView?.setSelectedRange(NSRange(location: 0, length: 0))
            coordinator.load(text)
        } else if coordinator.lastSyncedText != text {
            // Someone else changed the note, usually an agent. Every local edit updates
            // lastSyncedText at once, so this is never your own typing coming back.
            coordinator.load(text)
        }
        coordinator.reportContentHeight()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorRepresentable
        weak var textView: MarkdownTextView?
        var lastSyncedText = ""
        var currentTaskId: UUID?
        private var lastReportedHeight: CGFloat = -1

        init(_ parent: MarkdownEditorRepresentable) {
            self.parent = parent
        }

        func load(_ markdown: String) {
            lastSyncedText = markdown
            textView?.setMarkdown(markdown)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let markdown = textView.string
            lastSyncedText = markdown
            parent.text = markdown
            textView.restyle()
            reportContentHeight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            textView?.caretMoved()
        }

        func reportContentHeight() {
            guard parent.growsWithContent,
                  let textView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return }

            layoutManager.ensureLayout(for: container)
            let height = ceil(layoutManager.usedRect(for: container).height + textView.textContainerInset.height * 2)
            guard abs(height - lastReportedHeight) > 0.5 else { return }
            lastReportedHeight = height

            // Measured during a SwiftUI update, so the state change has to wait for the next pass.
            let report = parent.onContentHeightChange
            DispatchQueue.main.async {
                report(height)
            }
        }
    }
}
