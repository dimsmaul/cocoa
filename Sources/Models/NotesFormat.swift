import AppKit

/// Task notes are stored as Markdown, the one format both you and an agent can read and write.
public enum NotesFormat {
    /// Converts notes saved before Markdown (RTF, or `•` and `▎` line prefixes). Markdown passes through.
    public static func normalized(_ notes: String) -> String {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = notes
        if trimmed.hasPrefix("{\\rtf") || trimmed.hasPrefix("{\\urtf"),
           let data = notes.data(using: .utf8),
           let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            result = markdown(from: attributed)
        }
        guard result.contains("•") || result.contains("▎") else { return result }
        return result
            .replacingOccurrences(of: #"(?m)^([ \t]*)• "#, with: "$1- ", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^([ \t]*)▎ "#, with: "$1> ", options: .regularExpression)
    }

    /// One line of plain text for task cards, with the Markdown syntax removed.
    public static func preview(of notes: String) -> String {
        let removable = MarkdownParser.spans(in: notes).compactMap { span -> NSRange? in
            switch span.kind {
            case .marker, .listMarker, .orderedMarker, .taskBox, .codeFence, .tableDivider, .tablePipe, .horizontalRule:
                return span.range
            default:
                return nil
            }
        }
        let text = NSMutableString(string: notes)
        for range in removable.sorted(by: { $0.location > $1.location }) {
            text.deleteCharacters(in: range)
        }
        return (text as String)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func markdown(from attributed: NSAttributedString) -> String {
        var result = ""
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            let run = attributed.attributedSubstring(from: range).string
            let wrapper = wrapperMarker(for: attributes)
            result += run
                .components(separatedBy: "\n")
                .map { wrapped($0, in: wrapper) }
                .joined(separator: "\n")
        }
        return result.trimmingCharacters(in: .newlines)
    }

    /// Underline and color have no Markdown form, so they are dropped.
    private static func wrapperMarker(for attributes: [NSAttributedString.Key: Any]) -> String {
        var marker = ""
        if let font = attributes[.font] as? NSFont {
            let name = font.fontName.lowercased()
            if font.isFixedPitch || name.contains("mono") || name.contains("menlo") || name.contains("courier") {
                return "`"
            }
            let traits = NSFontManager.shared.traits(of: font)
            if traits.contains(.boldFontMask) { marker += "**" }
            if traits.contains(.italicFontMask) { marker += "*" }
        }
        if attributes[.strikethroughStyle] != nil { marker += "~~" }
        return marker
    }

    /// Keeps surrounding spaces outside the markers, because `** word **` is not valid Markdown.
    private static func wrapped(_ text: String, in marker: String) -> String {
        let core = text.trimmingCharacters(in: .whitespaces)
        guard !marker.isEmpty, !core.isEmpty else { return text }
        let leading = String(text.prefix { $0 == " " || $0 == "\t" })
        let trailing = String(text.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
        return leading + marker + core + String(marker.reversed()) + trailing
    }
}

public extension TaskItem {
    /// Plain text for task cards. Nil when there are no notes to show.
    var notesPreview: String? {
        let preview = NotesFormat.preview(of: notes)
        return preview.isEmpty ? nil : preview
    }

    /// Everything an agent needs to work on this task, as Markdown.
    var agentSummary: String {
        var lines = [
            "# \(title)",
            "",
            "- ID: \(id.uuidString)",
            "- Status: \(isCompleted ? "Completed" : "Open")",
            "- Board: \(board.rawValue)",
            "- List: \(listName)",
            "- Priority: \(priority.rawValue)",
            "- Estimate: \(estimatedMinutes)m",
            "- Time spent: \(formattedTimeSpent)"
        ]
        if let dueDate {
            lines.append("- Due: \(dueDate.formatted(date: .abbreviated, time: .omitted))")
        }
        if let recurrence {
            lines.append("- Repeat: \(recurrence.label)")
        }

        lines += ["", "## Notes", "", notes.isEmpty ? "(none)" : notes]

        if !subtasks.isEmpty {
            lines += ["", "## Subtasks", ""]
            func append(_ items: [SubtaskItem], depth: Int) {
                for item in items {
                    let indent = String(repeating: "  ", count: depth)
                    lines.append("\(indent)- [\(item.isCompleted ? "x" : " ")] \(item.title)")
                    append(item.subtasks, depth: depth + 1)
                }
            }
            append(subtasks, depth: 0)
        }

        if !comments.isEmpty {
            lines += ["", "## Comments", ""]
            lines += comments.map { "- \($0.author) (\($0.formattedDate)): \($0.content)" }
        }

        return lines.joined(separator: "\n")
    }
}
