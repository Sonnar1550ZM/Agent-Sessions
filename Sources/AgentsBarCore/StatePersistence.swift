import Foundation

public struct AgentsBarDocument: Codable, Equatable, Sendable {
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
            .appendingPathComponent("AgentsBar", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
    }

    public func load() throws -> AgentsBarDocument {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return AgentsBarDocument()
        }

        let data = try Data(contentsOf: stateURL)
        return try Self.decoder.decode(AgentsBarDocument.self, from: data)
    }

    public func save(_ document: AgentsBarDocument) throws {
        let directory = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(document)
        try data.write(to: stateURL, options: [.atomic])
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(AgentsBarDates.string(from: date))
        }
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = AgentsBarDates.date(from: value) {
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
