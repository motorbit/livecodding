import Foundation

/// Strips likely PII and secrets from free text before it becomes an analytics parameter
/// (e.g. an error description). Prefer sending enum categories; use this only when text is
/// unavoidable.
public enum AnalyticsSanitizer {
    public static func sanitize(_ text: String, maxLength: Int = 100) -> String {
        var result = text
        // Regex values aren't Sendable, so they're built per call instead of stored in statics.
        let rules: [(Regex<Substring>, String)] = [
            (#/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/#, "<email>"),
            (#/https?:\/\/\S+/#, "<url>"),
            (#/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/#, "<uuid>"),
            (#/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*/#, "<jwt>"),
            (#/[A-Za-z0-9_\-]{32,}/#, "<token>"),
            (#/\d{6,}/#, "<number>"),
        ]
        for (pattern, replacement) in rules {
            result = result.replacing(pattern, with: replacement)
        }
        return String(result.prefix(maxLength))
    }
}
