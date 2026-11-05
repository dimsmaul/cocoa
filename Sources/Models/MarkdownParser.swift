import Foundation

public enum MarkdownSpanKind: Equatable, Sendable {
    case heading(Int)
    case bold
    case italic
    case strikethrough
    case inlineCode
    case link(String)
    /// Syntax characters, hidden unless the caret is on their line.
    case marker
    case listMarker
    case orderedMarker
    /// A whole list line. `indent` is the visible width of its marker, in characters.
    case listItem(indent: Int)
    case taskBox(checked: Bool)
    case completedTask
    case quote
    case codeBlock
    case codeFence
    case tableRow(header: Bool)
    case tableDivider
    case tablePipe
    /// Extra columns to add after this character so table columns line up.
    case tablePadding(Int)
    case horizontalRule
}

public struct MarkdownSpan: Equatable, Sendable {
    public let range: NSRange
    public let kind: MarkdownSpanKind

    public init(range: NSRange, kind: MarkdownSpanKind) {
        self.range = range
        self.kind = kind
    }
}

/// Finds what each part of a Markdown note is, in place, so the text stored and the text
/// shown stay the same string: there is no conversion for you or an agent to lose data in.
public enum MarkdownParser {
    public static func spans(in text: String) -> [MarkdownSpan] {
        let source = text as NSString
        let lines = lineRanges(in: source)
        var spans: [MarkdownSpan] = []
        var isInFence = false
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if firstMatch(Pattern.fence, text, line) != nil {
                spans.append(MarkdownSpan(range: line, kind: .codeFence))
                isInFence.toggle()
                index += 1
            } else if isInFence {
                if line.length > 0 {
                    spans.append(MarkdownSpan(range: line, kind: .codeBlock))
                }
                index += 1
            } else if index + 1 < lines.count, isTableStart(text, source, header: line, divider: lines[index + 1]) {
                index = appendTable(text, source, lines: lines, start: index, to: &spans)
            } else {
                appendLine(text, line, to: &spans)
                index += 1
            }
        }

        return spans.enumerated()
            .sorted { ($0.element.range.location, $0.offset) < ($1.element.range.location, $1.offset) }
            .map(\.element)
    }

    // MARK: - Lines

    private static func lineRanges(in source: NSString) -> [NSRange] {
        var lines: [NSRange] = []
        var position = 0
        while position < source.length {
            var start = 0, end = 0, contentsEnd = 0
            source.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: position, length: 0))
            lines.append(NSRange(location: start, length: contentsEnd - start))
            position = end
        }
        return lines
    }

    private static func appendLine(_ text: String, _ line: NSRange, to spans: inout [MarkdownSpan]) {
        guard line.length > 0 else { return }

        if firstMatch(Pattern.rule, text, line) != nil {
            spans.append(MarkdownSpan(range: line, kind: .horizontalRule))
            return
        }

        var inlineStart = line.location

        if let match = firstMatch(Pattern.heading, text, line) {
            spans.append(MarkdownSpan(range: line, kind: .heading(match.range(at: 1).length)))
            spans.append(MarkdownSpan(range: match.range, kind: .marker))
            inlineStart = NSMaxRange(match.range)
        } else if let match = firstMatch(Pattern.quote, text, line) {
            spans.append(MarkdownSpan(range: line, kind: .quote))
            spans.append(MarkdownSpan(range: match.range, kind: .marker))
            inlineStart = NSMaxRange(match.range)
        } else if let match = firstMatch(Pattern.task, text, line) {
            let box = match.range(at: 3)
            let isChecked = (text as NSString).substring(with: box).lowercased() == "[x]"
            spans.append(MarkdownSpan(range: line, kind: .listItem(indent: match.range(at: 1).length + 4)))
            spans.append(MarkdownSpan(range: match.range(at: 2), kind: .marker))
            spans.append(MarkdownSpan(range: box, kind: .taskBox(checked: isChecked)))
            inlineStart = NSMaxRange(match.range)
            if isChecked, inlineStart < NSMaxRange(line) {
                spans.append(MarkdownSpan(range: NSRange(location: inlineStart, length: NSMaxRange(line) - inlineStart), kind: .completedTask))
            }
        } else if let match = firstMatch(Pattern.bullet, text, line) {
            spans.append(MarkdownSpan(range: line, kind: .listItem(indent: match.range.length)))
            spans.append(MarkdownSpan(range: match.range(at: 2), kind: .listMarker))
            inlineStart = NSMaxRange(match.range)
        } else if let match = firstMatch(Pattern.ordered, text, line) {
            spans.append(MarkdownSpan(range: line, kind: .listItem(indent: match.range.length)))
            spans.append(MarkdownSpan(range: match.range(at: 2), kind: .orderedMarker))
            inlineStart = NSMaxRange(match.range)
        }

        spans += inlineSpans(text, NSRange(location: inlineStart, length: NSMaxRange(line) - inlineStart))
    }

    // MARK: - Tables

    private static func isTableStart(_ text: String, _ source: NSString, header: NSRange, divider: NSRange) -> Bool {
        source.substring(with: header).contains("|")
            && source.substring(with: divider).contains("|")
            && firstMatch(Pattern.tableDivider, text, divider) != nil
    }

    /// Returns the index of the first line after the table.
    private static func appendTable(
        _ text: String,
        _ source: NSString,
        lines: [NSRange],
        start: Int,
        to spans: inout [MarkdownSpan]
    ) -> Int {
        var end = start + 2
        while end < lines.count, source.substring(with: lines[end]).contains("|") {
            end += 1
        }

        var rows: [(line: NSRange, isHeader: Bool, inline: [MarkdownSpan], cells: [NSRange], pipes: [NSRange])] = []
        for index in start..<end where index != start + 1 {
            let (cells, pipes) = tableCells(source, lines[index])
            rows.append((lines[index], index == start, inlineSpans(text, lines[index]), cells, pipes))
        }

        func visibleWidth(_ cell: NSRange, _ inline: [MarkdownSpan]) -> Int {
            let hidden = inline
                .filter { $0.kind == .marker }
                .reduce(0) { $0 + NSIntersectionRange($1.range, cell).length }
            return cell.length - hidden
        }

        var widths: [Int] = []
        for row in rows {
            for (column, cell) in row.cells.enumerated() {
                let width = visibleWidth(cell, row.inline)
                if column < widths.count {
                    widths[column] = max(widths[column], width)
                } else {
                    widths.append(width)
                }
            }
        }

        spans.append(MarkdownSpan(range: lines[start + 1], kind: .tableDivider))
        for row in rows {
            spans.append(MarkdownSpan(range: row.line, kind: .tableRow(header: row.isHeader)))
            spans += row.pipes.map { MarkdownSpan(range: $0, kind: .tablePipe) }
            spans += row.inline
            for (column, cell) in row.cells.enumerated() {
                let padding = widths[column] - visibleWidth(cell, row.inline)
                if padding > 0 {
                    // Padding sits on the cell's last character; an empty cell uses the pipe before it.
                    let location = cell.length > 0 ? NSMaxRange(cell) - 1 : max(cell.location - 1, 0)
                    spans.append(MarkdownSpan(range: NSRange(location: location, length: 1), kind: .tablePadding(padding)))
                }
            }
        }
        return end
    }

    private static func tableCells(_ source: NSString, _ line: NSRange) -> (cells: [NSRange], pipes: [NSRange]) {
        var pipes: [NSRange] = []
        for location in line.location..<NSMaxRange(line) where source.character(at: location) == 0x7C {
            if location == line.location || source.character(at: location - 1) != 0x5C {
                pipes.append(NSRange(location: location, length: 1))
            }
        }

        var cells: [NSRange] = []
        var cellStart = line.location
        for pipe in pipes {
            let cell = NSRange(location: cellStart, length: pipe.location - cellStart)
            if pipe.location != line.location || cell.length > 0 {
                if cellStart != line.location || !isBlank(source, cell) {
                    cells.append(cell)
                }
            }
            cellStart = NSMaxRange(pipe)
        }
        let last = NSRange(location: cellStart, length: NSMaxRange(line) - cellStart)
        if !isBlank(source, last) {
            cells.append(last)
        }
        return (cells, pipes)
    }

    private static func isBlank(_ source: NSString, _ range: NSRange) -> Bool {
        source.substring(with: range).trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Inline

    private static func inlineSpans(_ text: String, _ range: NSRange) -> [MarkdownSpan] {
        guard range.length > 0 else { return [] }
        var spans: [MarkdownSpan] = []
        var taken: [NSRange] = []

        func isFree(_ candidate: NSRange) -> Bool {
            !taken.contains { NSIntersectionRange($0, candidate).length > 0 }
        }

        for match in Pattern.inlineCode.matches(in: text, range: range) where isFree(match.range) {
            let content = match.range(at: 1)
            spans.append(MarkdownSpan(range: content, kind: .inlineCode))
            spans.append(MarkdownSpan(range: NSRange(location: match.range.location, length: 1), kind: .marker))
            spans.append(MarkdownSpan(range: NSRange(location: NSMaxRange(content), length: 1), kind: .marker))
            taken.append(match.range)
        }

        for match in Pattern.link.matches(in: text, range: range) where isFree(match.range) {
            let label = match.range(at: 1)
            let url = (text as NSString).substring(with: match.range(at: 2))
            spans.append(MarkdownSpan(range: label, kind: .link(url)))
            spans.append(MarkdownSpan(range: NSRange(location: match.range.location, length: 1), kind: .marker))
            spans.append(MarkdownSpan(
                range: NSRange(location: NSMaxRange(label), length: NSMaxRange(match.range) - NSMaxRange(label)),
                kind: .marker
            ))
            taken.append(match.range)
        }

        for match in Pattern.bareURL.matches(in: text, range: range) where isFree(match.range) {
            spans.append(MarkdownSpan(range: match.range, kind: .link((text as NSString).substring(with: match.range))))
            taken.append(match.range)
        }

        /// Delimited styles: only the delimiters are taken, so styles can nest inside each other.
        func appendDelimited(_ regex: NSRegularExpression, width: Int, kinds: [MarkdownSpanKind]) {
            for match in regex.matches(in: text, range: range) where isFree(match.range) {
                spans += kinds.map { MarkdownSpan(range: match.range, kind: $0) }
                let open = NSRange(location: match.range.location, length: width)
                let close = NSRange(location: NSMaxRange(match.range) - width, length: width)
                spans.append(MarkdownSpan(range: open, kind: .marker))
                spans.append(MarkdownSpan(range: close, kind: .marker))
                taken += [open, close]
            }
        }

        appendDelimited(Pattern.boldItalic, width: 3, kinds: [.bold, .italic])
        appendDelimited(Pattern.boldStars, width: 2, kinds: [.bold])
        appendDelimited(Pattern.boldUnderscores, width: 2, kinds: [.bold])
        appendDelimited(Pattern.strikethrough, width: 2, kinds: [.strikethrough])
        appendDelimited(Pattern.italicStars, width: 1, kinds: [.italic])
        appendDelimited(Pattern.italicUnderscores, width: 1, kinds: [.italic])
        return spans
    }

    private static func firstMatch(_ regex: NSRegularExpression, _ text: String, _ range: NSRange) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: range)
    }

    // The patterns are constants, so a compile failure is a programming error caught by the tests.
    private enum Pattern {
        private static func make(_ pattern: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern)
        }

        static let fence = make(#"^[ \t]*```[\w+-]*[ \t]*$"#)
        static let rule = make(#"^[ \t]*(?:-{3,}|\*{3,}|_{3,})[ \t]*$"#)
        static let heading = make(#"^(#{1,6})[ \t]+"#)
        static let quote = make(#"^[ \t]*>[ \t]?"#)
        static let task = make(#"^([ \t]*)([-*+][ \t])(\[[ xX]\])[ \t]"#)
        static let bullet = make(#"^([ \t]*)([-*+])[ \t]"#)
        static let ordered = make(#"^([ \t]*)(\d+[.)])[ \t]"#)
        static let tableDivider = make(#"^[ \t]*\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$"#)
        static let inlineCode = make(#"`([^`\n]+)`"#)
        static let link = make(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)
        static let bareURL = make(#"https?://[^\s<>()\[\]`]*[^\s<>()\[\]`.,;:!?'"]"#)
        static let boldItalic = make(#"\*\*\*(?=\S)(.+?)(?<=\S)\*\*\*"#)
        static let boldStars = make(#"\*\*(?=\S)(.+?)(?<=\S)\*\*"#)
        static let boldUnderscores = make(#"(?<![_\w])__(?=\S)(.+?)(?<=\S)__(?![_\w])"#)
        static let strikethrough = make(#"~~(?=\S)(.+?)(?<=\S)~~"#)
        static let italicStars = make(#"(?<![*\w])\*(?=[^\s*])([^*\n]+?)(?<=\S)\*(?![*\w])"#)
        static let italicUnderscores = make(#"(?<![_\w])_(?=[^\s_])([^_\n]+?)(?<=\S)_(?![_\w])"#)
    }
}
