import Foundation

/// Reads bounded text windows from large JSONL session files without loading
/// the whole file into memory.
public enum SessionFileTextReader {
    /// Returns up to `limit` bytes from the end of the file. When the read
    /// starts mid-file the first (partial) line is skipped so the result
    /// always begins at a line boundary.
    public static func tailText(from url: URL, limit: UInt64 = 1_000_000) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        return tailText(handle: handle, size: size, limit: limit)
    }

    /// Returns the head and tail of the file joined together, guaranteeing no
    /// byte is included twice: files within `headLimit + tailLimit` are read
    /// whole in a single pass, larger files contribute the head truncated at
    /// its last newline plus a tail that starts strictly after the head.
    public static func contextText(
        from url: URL,
        headLimit: Int = 128_000,
        tailLimit: UInt64 = 1_000_000
    ) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        guard size > UInt64(headLimit) + tailLimit else {
            try? handle.seek(toOffset: 0)
            let data = (try? handle.readToEnd()) ?? Data()
            return String(data: data, encoding: .utf8)
        }

        try? handle.seek(toOffset: 0)
        let headData = (try? handle.read(upToCount: headLimit)) ?? Data()
        guard let tail = tailText(handle: handle, size: size, limit: tailLimit) else {
            return nil
        }

        // Truncating at the newline byte keeps the head on a line boundary,
        // so a line cut mid-way (possibly mid-character) never reaches the
        // parser. The tail starts after byte `size - tailLimit > headLimit`,
        // so the two regions cannot overlap.
        let newline = UInt8(ascii: "\n")
        guard let lastNewlineIndex = headData.lastIndex(of: newline),
              let head = String(data: headData.prefix(through: lastNewlineIndex), encoding: .utf8) else {
            return tail
        }
        return head + tail
    }

    private static func tailText(handle: FileHandle, size: UInt64, limit: UInt64) -> String? {
        let start = size > limit ? size - limit : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        guard var text = String(data: data, encoding: .utf8) else {
            return nil
        }

        if start > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        return text
    }
}
