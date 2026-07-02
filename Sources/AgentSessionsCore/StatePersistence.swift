import Foundation

public struct AgentSessionsDocument: Codable, Equatable, Sendable {
    public var sessions: [AgentSession]

    public init(sessions: [AgentSession] = []) {
        self.sessions = sessions
    }
}

public final class StatePersistence: @unchecked Sendable {
    public let stateURL: URL

    public init(stateURL: URL = StatePersistence.defaultStateURL()) {
        self.stateURL = stateURL
    }

    public static func defaultStateURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Agent Sessions", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
    }

    public func load() throws -> AgentSessionsDocument {
        if FileManager.default.fileExists(atPath: stateURL.path) {
            return try loadDocument(from: stateURL)
        }

        return AgentSessionsDocument()
    }

    public func save(_ document: AgentSessionsDocument) throws {
        let directory = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(document)
        try data.write(to: stateURL, options: [.atomic])
    }

    private func loadDocument(from url: URL) throws -> AgentSessionsDocument {
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(AgentSessionsDocument.self, from: data)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(AgentSessionsDates.string(from: date))
        }
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = AgentSessionsDates.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }
        return decoder
    }()
}
