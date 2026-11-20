import Foundation

/// Mots surlignés des accroches : un passage entre étoiles (« Prêt en *5 minutes* ») est surligné en style
/// dynamique ; les autres styles affichent l'accroche sans les étoiles. Même règle que le back-office
/// (shared/utils/boost.ts, hookSegments) et le SDK Android (Hooks.kt).
enum Hooks {
    /// Texte sans étoiles et positions (UTF-16, pour NSAttributedString) des passages surlignés
    struct Marked: Equatable {
        let text: String
        let marks: [NSRange]
    }

    private static let marked = try! NSRegularExpression(pattern: "\\*([^*]+)\\*")

    static func parse(_ hook: String) -> Marked {
        let source = hook as NSString
        let text = NSMutableString()
        var marks: [NSRange] = []
        var last = 0
        for match in marked.matches(in: hook, range: NSRange(location: 0, length: source.length)) {
            text.append(source.substring(with: NSRange(location: last, length: match.range.location - last)))
            let word = source.substring(with: match.range(at: 1))
            marks.append(NSRange(location: text.length, length: (word as NSString).length))
            text.append(word)
            last = match.range.location + match.range.length
        }
        text.append(source.substring(from: last))
        return Marked(text: text as String, marks: marks)
    }

    static func plain(_ hook: String) -> String {
        return parse(hook).text
    }
}
