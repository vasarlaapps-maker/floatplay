import Foundation

enum YouTubeHelper {

    /// Extracts an 11-character YouTube video ID from any common URL format,
    /// a short youtu.be link, an embed URL, or a bare video ID.
    static func extractVideoID(from input: String) -> String {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }

        // 1. Full youtube.com watch URL — ?v=XXXXXXXXXXX
        if let components = URLComponents(string: raw),
           let host = components.host,
           host.contains("youtube.com"),
           let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value,
           isValidID(videoID) {
            return videoID
        }

        // 2. Short youtu.be/XXXXXXXXXXX URL
        if let url = URL(string: raw),
           let host = url.host,
           host == "youtu.be" {
            let id = url.lastPathComponent
            if isValidID(id) { return id }
        }

        // 3. Embed URL — youtube.com/embed/XXXXXXXXXXX
        if raw.contains("/embed/") {
            let parts = raw.components(separatedBy: "/embed/")
            if let segment = parts.last {
                let id = segment.components(separatedBy: "?").first ?? segment
                if isValidID(id) { return id }
            }
        }

        // 4. Shorts URL — youtube.com/shorts/XXXXXXXXXXX
        if raw.contains("/shorts/") {
            let parts = raw.components(separatedBy: "/shorts/")
            if let segment = parts.last {
                let id = segment.components(separatedBy: "?").first ?? segment
                if isValidID(id) { return id }
            }
        }

        // 5. Bare 11-char video ID
        if isValidID(raw) { return raw }

        return ""
    }

    /// YouTube video IDs are exactly 11 characters: letters, digits, `-`, `_`.
    private static func isValidID(_ id: String) -> Bool {
        guard id.count == 11 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
