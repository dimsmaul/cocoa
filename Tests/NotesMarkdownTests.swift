import AppKit
import Foundation
import Testing
@testable import CocoaApp

// Pure logic only: must never create TaskStore or touch AppSettings.shared.

private func texts(_ markdown: String, where matches: (MarkdownSpanKind) -> Bool) -> [String] {
    let source = markdown as NSString
    return MarkdownParser.spans(in: markdown)
        .filter { matches($0.kind) }
        .map { source.substring(with: $0.range) }
}

// MARK: - Block parsing

@Test func headingHidesHashesAndKeepsLevel() {
    let md = "## Plan"
    #expect(texts(md) { $0 == .heading(2) } == ["## Plan"])
    #expect(texts(md) { $0 == .marker } == ["## "])
}

@Test func hashWithoutSpaceIsNotAHeading() {
    #expect(texts("#tag") { if case .heading = $0 { return true } else { return false } }.isEmpty)
}

@Test func bulletMarkerIsFoundAtAnyIndent() {
    #expect(texts("- one\n  * two\n+ three") { $0 == .listMarker } == ["-", "*", "+"])
}

@Test func orderedMarkerIsFound() {
    #expect(texts("12. item") { $0 == .orderedMarker } == ["12."])
}

@Test func taskBoxKnowsItsState() {
    let md = "- [ ] open\n- [x] done"
    #expect(texts(md) { $0 == .taskBox(checked: false) } == ["[ ]"])
    #expect(texts(md) { $0 == .taskBox(checked: true) } == ["[x]"])
    #expect(texts(md) { $0 == .completedTask } == ["done"])
    #expect(texts(md) { $0 == .listMarker }.isEmpty)
    #expect(texts(md) { $0 == .marker } == ["- ", "- "])
}

@Test func quoteHidesMarker() {
    let md = "> careful"
    #expect(texts(md) { $0 == .quote } == ["> careful"])
    #expect(texts(md) { $0 == .marker } == ["> "])
}

@Test func horizontalRuleIsRecognized() {
    #expect(texts("---") { $0 == .horizontalRule } == ["---"])
}

@Test func codeFenceContentGetsNoInlineStyling() {
    let md = "```swift\nlet a = **b**\n- no list\n```\n**real**"
    #expect(texts(md) { $0 == .codeFence } == ["```swift", "```"])
    #expect(texts(md) { $0 == .codeBlock } == ["let a = **b**", "- no list"])
    #expect(texts(md) { $0 == .bold } == ["**real**"])
    #expect(texts(md) { $0 == .listMarker }.isEmpty)
}

@Test func unclosedFenceRunsToTheEnd() {
    #expect(texts("```\ncode\nmore") { $0 == .codeBlock } == ["code", "more"])
}

// MARK: - Inline parsing

@Test func inlineStylesAreFoundWithHiddenMarkers() {
    let md = "**b** *i* ~~s~~ `c`"
    #expect(texts(md) { $0 == .bold } == ["**b**"])
    #expect(texts(md) { $0 == .italic } == ["*i*"])
    #expect(texts(md) { $0 == .strikethrough } == ["~~s~~"])
    #expect(texts(md) { $0 == .inlineCode } == ["c"])
    #expect(texts(md) { $0 == .marker } == ["**", "**", "*", "*", "~~", "~~", "`", "`"])
}

@Test func boldItalicCombines() {
    let md = "***both***"
    #expect(texts(md) { $0 == .bold } == ["***both***"])
    #expect(texts(md) { $0 == .italic } == ["***both***"])
    #expect(texts(md) { $0 == .marker } == ["***", "***"])
}

@Test func starsInsideInlineCodeStayLiteral() {
    let md = "`a*b*c`"
    #expect(texts(md) { $0 == .italic }.isEmpty)
    #expect(texts(md) { $0 == .inlineCode } == ["a*b*c"])
}

@Test func snakeCaseIsNotItalic() {
    #expect(texts("my_var_name") { $0 == .italic }.isEmpty)
}

@Test func spacedAsterisksAreNotItalic() {
    #expect(texts("2 * 3 * 4") { $0 == .italic }.isEmpty)
}

@Test func linkKeepsLabelVisibleAndCarriesURL() {
    let md = "see [docs](https://a.dev/x) now"
    #expect(texts(md) { $0 == .link("https://a.dev/x") } == ["docs"])
    #expect(texts(md) { $0 == .marker } == ["[", "](https://a.dev/x)"])
}

@Test func bareURLBecomesLink() {
    let md = "at https://a.dev/x."
    #expect(texts(md) { $0 == .link("https://a.dev/x") } == ["https://a.dev/x"])
}

@Test func unicodeOffsetsStayCorrect() {
    let md = "🍫 **ok**"
    #expect(texts(md) { $0 == .bold } == ["**ok**"])
}

// MARK: - Tables

@Test func tableMarksPartsAndPadsColumns() {
    let md = "| a | long |\n|---|---|\n| wider | b |"
    #expect(MarkdownParser.spans(in: md).contains { $0.kind == .tableRow(header: true) })
    #expect(texts(md) { $0 == .tableRow(header: false) } == ["| wider | b |"])
    #expect(texts(md) { $0 == .tableDivider } == ["|---|---|"])
    #expect(texts(md) { $0 == .tablePipe }.count == 6)

    // Column widths are 7 ("wider" + spaces) and 6 (" long "), so each shorter cell is padded by the difference.
    let padding = MarkdownParser.spans(in: md).compactMap { span -> Int? in
        if case .tablePadding(let columns) = span.kind { return columns }
        return nil
    }
    #expect(padding == [4, 3])
}

@Test func tableWidthIgnoresHiddenMarkers() {
    let md = "| **ab** |\n|---|\n| abcd |"
    let padding = MarkdownParser.spans(in: md).compactMap { span -> Int? in
        if case .tablePadding(let columns) = span.kind { return columns }
        return nil
    }
    #expect(padding == [2])
}

@Test func pipeWithoutDividerIsNotATable() {
    #expect(texts("a | b\nc | d") { $0 == .tablePipe }.isEmpty)
}

// MARK: - Editing commands

@Test func wrapAddsMarkersAndKeepsSelection() {
    let edit = MarkdownEditing.toggleWrap(text: "say hello", selection: NSRange(location: 4, length: 5), marker: "**")
    #expect(edit.text == "say **hello**")
    #expect(edit.selection == NSRange(location: 6, length: 5))
}

@Test func wrapRemovesExistingMarkers() {
    let edit = MarkdownEditing.toggleWrap(text: "say **hello**", selection: NSRange(location: 6, length: 5), marker: "**")
    #expect(edit.text == "say hello")
    #expect(edit.selection == NSRange(location: 4, length: 5))
}

@Test func wrapWithoutSelectionPlacesCaretInside() {
    let edit = MarkdownEditing.toggleWrap(text: "ab", selection: NSRange(location: 1, length: 0), marker: "`")
    #expect(edit.text == "a``b")
    #expect(edit.selection == NSRange(location: 2, length: 0))
}

@Test func prefixAppliesToEverySelectedLine() {
    let edit = MarkdownEditing.togglePrefix(text: "a\nb", selection: NSRange(location: 0, length: 3), style: .bullet)
    #expect(edit.text == "- a\n- b")
}

@Test func prefixTogglesOffWhenAllLinesHaveIt() {
    let edit = MarkdownEditing.togglePrefix(text: "- a\n- b", selection: NSRange(location: 0, length: 7), style: .bullet)
    #expect(edit.text == "a\nb")
}

@Test func prefixReplacesADifferentListStyle() {
    let edit = MarkdownEditing.togglePrefix(text: "- a", selection: NSRange(location: 2, length: 0), style: .task)
    #expect(edit.text == "- [ ] a")
    #expect(edit.selection == NSRange(location: 6, length: 0))
}

@Test func numberedPrefixCounts() {
    let edit = MarkdownEditing.togglePrefix(text: "a\n\nb", selection: NSRange(location: 0, length: 4), style: .numbered)
    #expect(edit.text == "1. a\n\n2. b")
}

@Test func headingCommandSetsLevelAndTogglesOff() {
    let set = MarkdownEditing.togglePrefix(text: "Plan", selection: NSRange(location: 0, length: 0), style: .heading(2))
    #expect(set.text == "## Plan")
    let off = MarkdownEditing.togglePrefix(text: "## Plan", selection: NSRange(location: 3, length: 0), style: .heading(2))
    #expect(off.text == "Plan")
}

@Test func linkCommandSelectsTheURLPlaceholder() {
    let edit = MarkdownEditing.insertLink(text: "see docs", selection: NSRange(location: 4, length: 4))
    #expect(edit.text == "see [docs](https://)")
    #expect(edit.selection == NSRange(location: 11, length: 8))
}

@Test func codeBlockCommandFencesWholeLines() {
    let edit = MarkdownEditing.insertCodeBlock(text: "a\nb\nc", selection: NSRange(location: 2, length: 0))
    #expect(edit.text == "a\n```\nb\n```\nc")
}

@Test(arguments: [
    ("- item", "\n- "),
    ("  * item", "\n  * "),
    ("3. item", "\n4. "),
    ("- [x] done", "\n- [ ] "),
    ("> quote", "\n> "),
])
func enterContinuesBlock(line: String, inserted: String) {
    #expect(MarkdownEditing.newlineAction(forLine: line) == .insert(inserted))
}

@Test(arguments: ["- ", "1. ", "- [ ] ", "> "])
func enterOnEmptyItemExitsBlock(line: String) {
    #expect(MarkdownEditing.newlineAction(forLine: line) == .exitBlock)
}

@Test func enterOnNormalTextDoesNothingSpecial() {
    #expect(MarkdownEditing.newlineAction(forLine: "plain") == .none)
}

// MARK: - Typing shortcuts

@Test(arguments: [
    ("[]", "- [ ] "),
    ("[ ]", "- [ ] "),
    ("[x]", "- [x] "),
    ("[X]", "- [x] "),
    ("  []", "  - [ ] "),
    ("- []", "- [ ] "),
    ("* [x]", "* [x] "),
])
func spaceAfterBracketsMakesACheckbox(typed: String, expected: String) {
    #expect(MarkdownEditing.autoFormat(beforeCaret: typed) == expected)
}

@Test(arguments: ["", "[", "[a]", "text []", "- item"])
func otherTextIsNotAutoFormatted(typed: String) {
    #expect(MarkdownEditing.autoFormat(beforeCaret: typed) == nil)
}

@Test func enterAfterOpeningFenceClosesTheBlock() throws {
    let edit = try #require(MarkdownEditing.autoCloseFence(text: "```swift", caret: 8))
    #expect(edit.text == "```swift\n\n```")
    #expect(edit.selection == NSRange(location: 9, length: 0))
}

@Test func enterAfterClosingFenceAddsNothing() {
    let text = "```\ncode\n```"
    #expect(MarkdownEditing.autoCloseFence(text: text, caret: (text as NSString).length) == nil)
}

@Test func enterInTheMiddleOfAFenceLineAddsNothing() {
    #expect(MarkdownEditing.autoCloseFence(text: "```swift", caret: 3) == nil)
}

// MARK: - Saved notes

@Test func markdownNotesAreLeftUntouched() {
    let notes = "# Plan\n\n- [ ] do **it**\n"
    #expect(NotesFormat.normalized(notes) == notes)
}

@Test func oldBulletAndQuoteCharactersBecomeMarkdown() {
    #expect(NotesFormat.normalized("• a\n▎ b\nc") == "- a\n> b\nc")
}

@Test func oldRichTextBecomesMarkdown() throws {
    let base = NSFont.systemFont(ofSize: 14)
    let bold = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
    let attributed = NSMutableAttributedString(string: "plain ", attributes: [.font: base])
    attributed.append(NSAttributedString(string: "strong", attributes: [.font: bold]))
    attributed.append(NSAttributedString(string: " ", attributes: [.font: base]))
    attributed.append(NSAttributedString(string: "code", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]))
    attributed.append(NSAttributedString(string: "\n• item", attributes: [.font: base]))

    let data = try attributed.data(
        from: NSRange(location: 0, length: attributed.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
    let rtf = try #require(String(data: data, encoding: .utf8))

    #expect(NotesFormat.normalized(rtf) == "plain **strong** `code`\n- item")
}

@Test func unreadableRichTextIsKeptRatherThanLost() {
    let broken = "{\\rtf1 not really"
    #expect(!NotesFormat.normalized(broken).isEmpty)
}

@Test func previewStripsMarkdownAndJoinsLines() {
    let notes = "# Title\n\n- [ ] do **it**\n1. use `x`\n> quoted [link](https://a.dev)"
    #expect(NotesFormat.preview(of: notes) == "Title do it use x quoted link")
}

@Test func previewSkipsCodeFenceMarkers() {
    #expect(NotesFormat.preview(of: "```swift\nlet a = 1\n```") == "let a = 1")
}

@Test func oldNotesAreConvertedWhenTasksLoad() throws {
    let json = #"[{"id":"7D0F6A11-6C1B-4E2D-9C1A-1F0E2D3C4B5A","title":"t","notes":"• old"}]"#
    let tasks = try JSONDecoder().decode([TaskItem].self, from: Data(json.utf8))
    #expect(tasks[0].notes == "- old")
}

@Test func oldNotesFromCloudAreConverted() {
    let dto = SupabaseTaskDTO(id: UUID(), title: "t", notes: "• old")
    #expect(dto.toTaskItem().notes == "- old")
}

// MARK: - Agent access

@Test func agentSummaryCarriesWhatAnAgentNeeds() {
    let parent = SubtaskItem(title: "Parent", isCompleted: true, subtasks: [SubtaskItem(title: "Child")])
    let task = TaskItem(
        title: "Ship it",
        notes: "## Plan\n- step",
        estimatedMinutes: 30,
        priority: .high,
        listName: "Work",
        subtasks: [parent],
        comments: [TaskComment(author: "You", content: "looks good")],
        board: .today
    )
    let summary = task.agentSummary

    #expect(summary.contains("# Ship it"))
    #expect(summary.contains(task.id.uuidString))
    #expect(summary.contains("Priority: High"))
    #expect(summary.contains("## Plan\n- step"))
    #expect(summary.contains("- [x] Parent"))
    #expect(summary.contains("  - [ ] Child"))
    #expect(summary.contains("looks good"))
}

// MARK: - HTTP framing

@Test func httpRequestWaitsForTheFullBody() {
    let headers = "POST /mcp HTTP/1.1\r\nContent-Length: 5\r\n\r\n"
    #expect(!HTTPRequestFraming.isComplete(Data("POST /mcp HTT".utf8)))
    #expect(!HTTPRequestFraming.isComplete(Data(headers.utf8)))
    #expect(!HTTPRequestFraming.isComplete(Data((headers + "abc").utf8)))
    #expect(HTTPRequestFraming.isComplete(Data((headers + "abcde").utf8)))
}

@Test func httpContentLengthCountsBytesNotCharacters() {
    let headers = "POST /mcp HTTP/1.1\r\ncontent-length: 4\r\n\r\n"
    #expect(HTTPRequestFraming.isComplete(Data((headers + "🍫").utf8)))
}

@Test func httpRequestWithoutBodyIsComplete() {
    #expect(HTTPRequestFraming.isComplete(Data("GET /status HTTP/1.1\r\nHost: x\r\n\r\n".utf8)))
}
