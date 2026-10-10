@preconcurrency import Network
import Foundation

public final class TCPCommandServer: @unchecked Sendable {
    public enum Framing: Sendable {
        case semicolon
        case newline

        fileprivate var delimiter: UInt8 {
            switch self {
            case .semicolon: Character(";").asciiValue!
            case .newline: Character("\n").asciiValue!
            }
        }
    }

    public typealias Handler = @Sendable (String) async -> String?
    public typealias DisconnectHandler = @Sendable () async -> Void
    public typealias EventHandler = @Sendable (String) -> Void

    private let queue: DispatchQueue
    private let framing: Framing
    private let handler: Handler
    private let onDisconnect: DisconnectHandler
    private let onEvent: EventHandler
    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    public init(
        label: String,
        framing: Framing,
        handler: @escaping Handler,
        onDisconnect: @escaping DisconnectHandler = {},
        onEvent: @escaping EventHandler = { _ in }
    ) {
        queue = DispatchQueue(label: label)
        self.framing = framing
        self.handler = handler
        self.onDisconnect = onDisconnect
        self.onEvent = onEvent
    }

    public func start(port: UInt16) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw XCatError.server("Invalid TCP port \(port).")
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: endpointPort)

        let newListener = try NWListener(using: parameters)
        newListener.stateUpdateHandler = { [onEvent] state in
            switch state {
            case .ready:
                onEvent("Listening on 127.0.0.1:\(port)")
            case let .failed(error):
                onEvent("Listener failed on port \(port): \(error)")
            case .cancelled:
                onEvent("Listener stopped on port \(port)")
            default:
                break
            }
        }
        newListener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        lock.withLock {
            listener?.cancel()
            listener = newListener
        }
        newListener.start(queue: queue)
    }

    public func stop() {
        let activeConnections = lock.withLock {
            listener?.cancel()
            listener = nil
            let values = Array(connections.values)
            connections.removeAll()
            return values
        }
        activeConnections.forEach { $0.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        let session = ConnectionSession(framing: framing, handler: handler, onDisconnect: onDisconnect)
        let identifier = ObjectIdentifier(connection)
        lock.withLock { connections[identifier] = connection }
        connection.stateUpdateHandler = { [weak self, onEvent] state in
            switch state {
            case .ready:
                onEvent("Client connected")
            case let .failed(error):
                onEvent("Client failed: \(error)")
                self?.removeConnection(identifier)
                Task { await session.disconnect() }
            case .cancelled:
                onEvent("Client disconnected")
                self?.removeConnection(identifier)
                Task { await session.disconnect() }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection, session: session)
    }

    private func removeConnection(_ identifier: ObjectIdentifier) {
        lock.withLock { _ = connections.removeValue(forKey: identifier) }
    }

    private func receive(on connection: NWConnection, session: ConnectionSession) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, complete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let data, !data.isEmpty {
                Task {
                    let responses = await session.ingest(data)
                    self.send(responses, index: 0, on: connection) {
                        if complete || error != nil {
                            connection.cancel()
                        } else {
                            self.receive(on: connection, session: session)
                        }
                    }
                }
            } else if complete || error != nil {
                connection.cancel()
            } else {
                self.receive(on: connection, session: session)
            }
        }
    }

    private func send(
        _ responses: [Data],
        index: Int,
        on connection: NWConnection,
        completion: @escaping @Sendable () -> Void
    ) {
        guard index < responses.count else {
            completion()
            return
        }
        connection.send(content: responses[index], completion: .contentProcessed { [weak self] error in
            if error != nil {
                connection.cancel()
                return
            }
            self?.send(responses, index: index + 1, on: connection, completion: completion)
        })
    }
}

private actor ConnectionSession {
    private let delimiter: UInt8
    private let handler: TCPCommandServer.Handler
    private let onDisconnect: TCPCommandServer.DisconnectHandler
    private var buffer = Data()
    private var didDisconnect = false

    init(
        framing: TCPCommandServer.Framing,
        handler: @escaping TCPCommandServer.Handler,
        onDisconnect: @escaping TCPCommandServer.DisconnectHandler
    ) {
        delimiter = framing.delimiter
        self.handler = handler
        self.onDisconnect = onDisconnect
    }

    func ingest(_ data: Data) async -> [Data] {
        buffer.append(data)
        if buffer.count > 65_536 {
            buffer.removeAll(keepingCapacity: true)
            return []
        }

        var responses: [Data] = []
        while let delimiterIndex = buffer.firstIndex(of: delimiter) {
            let commandData = buffer[..<delimiterIndex]
            buffer.removeSubrange(...delimiterIndex)
            guard let command = String(data: commandData, encoding: .utf8) else { continue }
            if let response = await handler(command), let responseData = response.data(using: .utf8) {
                responses.append(responseData)
            }
        }
        return responses
    }

    func disconnect() async {
        guard !didDisconnect else { return }
        didDisconnect = true
        await onDisconnect()
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
