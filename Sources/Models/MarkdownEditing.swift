import Foundation

public struct MarkdownEdit: Equatable, Sendable {
    public let text: String
    public let selection: NSRange
}

public enum MarkdownLineStyle: Equatable, Sendable {
    case bullet
    case numbered
    case task
    case quote
    case heading(Int)
}

public enum MarkdownNewlineAction: Equatable, Sendable {
    case none
    case exitBlock
    case insert(String)
}

/// Text changes behind the editor's toolbar and shortcuts.
public enum MarkdownEditing {
    public static func toggleWrap(text: String, selection: NSRange, marker: String) -> MarkdownEdit {
        let source = text as NSString
        let width = (marker as NSString).length
        let selected = source.substring(with: selection)
        let hasBefore = selection.location >= width
            && source.substring(with: NSRange(location: selection.location - width, length: width)) == marker
        let afterEnd = NSMaxRange(selection) + width
        let hasAfter = afterEnd <= source.length
            && source.substring(with: NSRange(location: NSMaxRange(selection), length: width)) == marker

        if selection.length > 0, hasBefore, hasAfter {
            let outer = NSRange(location: selection.location - width, length: selection.length + width * 2)
            return MarkdownEdit(
                text: source.replacingCharacters(in: outer, with: selected),
                selection: NSRange(location: outer.location, length: selection.length)
            )
        }
        return MarkdownEdit(
            text: source.replacingCharacters(in: selection, with: marker + selected + marker),
            selection: NSRange(location: selection.location + width, length: selection.length)
        )
    }

    public static func togglePrefix(text: String, selection: NSRange, style: MarkdownLineStyle) -> MarkdownEdit {
        let source = text as NSString
        let block = trailingNewlineRemoved(source.lineRange(for: selection), in: source)
        let lines = source.substring(with: block).components(separatedBy: "\n")
        let filled = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let isRemoving = !filled.isEmpty && filled.allSatisfy { hasStyle($0, style) }

        var counter = 1
        let newLines = lines.map { line -> String in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            let (indent, body) = splitPrefix(line)
            if isRemoving {
                return indent + body
            }
            defer { counter += 1 }
            return indent + prefix(for: style, number: counter) + body
        }

        let replacement = newLines.joined(separator: "\n")
        let newLength = (replacement as NSString).length
        let result = source.replacingCharacters(in: block, with: replacement)

        if selection.length > 0 {
            return MarkdownEdit(text: result, selection: NSRange(location: block.location, length: newLength))
        }
        let caret = max(block.location, selection.location + newLength - block.length)
        return MarkdownEdit(text: result, selection: NSRange(location: caret, length: 0))
    }

    public static func insertLink(text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString
        let label = selection.length > 0 ? source.substring(with: selection) : "link"
        let placeholder = "https://"
        let urlStart = selection.location + (label as NSString).length + 3
        return MarkdownEdit(
            text: source.replacingCharacters(in: selection, with: "[\(label)](\(placeholder))"),
            selection: NSRange(location: urlStart, length: (placeholder as NSString).length)
        )
    }

    public static func insertCodeBlock(text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString
        let block = trailingNewlineRemoved(source.lineRange(for: selection), in: source)
        let content = source.substring(with: block)
        let opening = "```\n"
        return MarkdownEdit(
            text: source.replacingCharacters(in: block, with: opening + content + "\n```"),
            selection: NSRange(location: block.location + (opening as NSString).length, length: block.length)
        )
    }

    /// What pressing Space should turn the text before the caret into, if anything.
    /// Other typed syntax (`- `, `1. `, `> `, `# `) already renders as you type it.
    public static func autoFormat(beforeCaret text: String) -> String? {
        let source = text as NSString
        guard let match = checkboxShorthand.firstMatch(in: text, range: NSRange(location: 0, length: source.length)) else {
            return nil
        }
        let indent = source.substring(with: match.range(at: 1))
        let marker = match.range(at: 2).location == NSNotFound ? "- " : source.substring(with: match.range(at: 2))
        let isChecked = source.substring(with: match.range(at: 3)).lowercased() == "x"
        return "\(indent)\(marker)[\(isChecked ? "x" : " ")] "
    }

    /// Enter at the end of an opening ``` adds the closing fence and puts the caret between them.
    public static func autoCloseFence(text: String, caret: Int) -> MarkdownEdit? {
        let source = text as NSString
        let line = source.lineRange(for: NSRange(location: caret, length: 0))
        let content = source.substring(with: line).trimmingCharacters(in: .newlines)
        guard caret == line.location + (content as NSString).length,
              content.range(of: #"^[ \t]*```[\w+-]*[ \t]*$"#, options: .regularExpression) != nil else {
            return nil
        }

        // An odd number of fences means this one has nothing closing it yet.
        let fenceCount = MarkdownParser.spans(in: text).filter { $0.kind == .codeFence }.count
        guard fenceCount % 2 == 1 else { return nil }

        return MarkdownEdit(
            text: source.replacingCharacters(in: NSRange(location: caret, length: 0), with: "\n\n```"),
            selection: NSRange(location: caret + 1, length: 0)
        )
    }

    private static let checkboxShorthand = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+][ \t])?\[( ?|[xX])\]$"#)

    /// What Enter should do at the end of `line`.
    public static func newlineAction(forLine line: String) -> MarkdownNewlineAction {
        guard let match = line.range(of: #"^[ \t]*(?:[-*+][ \t]\[[ xX]\][ \t]|[-*+][ \t]|\d+[.)][ \t]|>[ \t]?)"#, options: .regularExpression) else {
            return .none
        }
        if line[match.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty {
            return .exitBlock
        }

        let marker = String(line[match])
        if marker.range(of: #"\[[ xX]\]"#, options: .regularExpression) != nil {
            return .insert("\n" + marker.replacingOccurrences(of: #"\[[xX]\]"#, with: "[ ]", options: .regularExpression))
        }
        if let digits = marker.range(of: #"\d+"#, options: .regularExpression), let number = Int(marker[digits]) {
            return .insert("\n" + marker.replacingCharacters(in: digits, with: String(number + 1)))
        }
        return .insert("\n" + marker)
    }

    // MARK: - Helpers

    private static func trailingNewlineRemoved(_ range: NSRange, in source: NSString) -> NSRange {
        var length = range.length
        while length > 0, source.character(at: range.location + length - 1) == 0x0A {
            length -= 1
        }
        return NSRange(location: range.location, length: length)
    }

    private static func prefix(for style: MarkdownLineStyle, number: Int) -> String {
        switch style {
        case .bullet: return "- "
        case .numbered: return "\(number). "
        case .task: return "- [ ] "
        case .quote: return "> "
        case .heading(let level): return String(repeating: "#", count: level) + " "
        }
    }

    private static func pattern(for style: MarkdownLineStyle) -> String {
        switch style {
        case .bullet: return #"^[ \t]*[-*+][ \t](?!\[[ xX]\][ \t])"#
        case .numbered: return #"^[ \t]*\d+[.)][ \t]"#
        case .task: return #"^[ \t]*[-*+][ \t]\[[ xX]\][ \t]"#
        case .quote: return #"^[ \t]*>[ \t]?"#
        case .heading(let level): return "^#{\(level)}[ \\t]+"
        }
    }

    private static func hasStyle(_ line: String, _ style: MarkdownLineStyle) -> Bool {
        line.range(of: pattern(for: style), options: .regularExpression) != nil
    }

    private static func splitPrefix(_ line: String) -> (indent: String, body: String) {
        let anyPrefix = #"^([ \t]*)(?:#{1,6}[ \t]+|>[ \t]?|[-*+][ \t]\[[ xX]\][ \t]|[-*+][ \t]|\d+[.)][ \t])?"#
        guard let match = line.range(of: anyPrefix, options: .regularExpression) else { return ("", line) }
        let indent = String(line[match].prefix { $0 == " " || $0 == "\t" })
        return (indent, String(line[match.upperBound...]))
    }
}
