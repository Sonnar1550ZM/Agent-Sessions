@preconcurrency import Network
import Foundation

public enum EventServerError: Error, LocalizedError {
    case invalidPort(UInt16)

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            "Invalid port: \(port)"
        }
    }
}

public final class EventServer: @unchecked Sendable {
    public typealias Handler = @Sendable (AgentEvent) -> Void

    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "app.agentsessions.event-server")
    private let handler: Handler
    private var listener: NWListener?

    public init(host: String = "127.0.0.1", port: UInt16 = 7823, handler: @escaping Handler) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw EventServerError.invalidPort(port)
        }
        if let address = IPv4Address(host) {
            self.host = .ipv4(address)
        } else {
            self.host = NWEndpoint.Host(host)
        }
        self.port = endpointPort
        self.handler = handler
    }

    public func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: host, port: port)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed = state {
                // NWListener cannot recover after failed; the app can be relaunched.
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if error != nil {
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if let body = Self.extractBody(from: nextBuffer) {
                self.handle(body, connection: connection)
                return
            }

            if isComplete {
                self.respond(status: "400 Bad Request", connection: connection)
                return
            }

            self.receive(on: connection, buffer: nextBuffer)
        }
    }

    private func handle(_ body: Data, connection: NWConnection) {
        do {
            let event = try Self.decoder.decode(AgentEvent.self, from: body)
            handler(event)
            respond(status: "204 No Content", connection: connection)
        } catch {
            respond(status: "400 Bad Request", connection: connection)
        }
    }

    private func respond(status: String, connection: NWConnection) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func extractBody(from request: Data) -> Data? {
        guard let headerEndRange = request.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = request[..<headerEndRange.lowerBound]
        guard let headers = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let contentLength = headers
            .split(separator: "\r\n")
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else {
                    return nil
                }
                guard parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length" else {
                    return nil
                }
                return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .first ?? 0

        let bodyStart = headerEndRange.upperBound
        let availableBodyCount = request.distance(from: bodyStart, to: request.endIndex)
        guard availableBodyCount >= contentLength else {
            return nil
        }

        return Data(request[bodyStart..<request.index(bodyStart, offsetBy: contentLength)])
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = AgentSessionsDates.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date")
        }
        return decoder
    }()
}
