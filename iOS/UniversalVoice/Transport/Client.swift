import Foundation
import Network
import os
import UniversalVoiceProtocol

final class ContinuationOnce<T: Sendable>: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)
    private let continuation: CheckedContinuation<T, Error>

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<T, Error>) {
        let shouldFire = lock.withLock { fired in
            if fired { return false }
            fired = true
            return true
        }
        guard shouldFire else { return }
        switch result {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}

actor Client {
    enum ClientState: Sendable, Equatable {
        case idle
        case connecting
        case handshaking
        case connected
        case failed(String)
    }

    enum ClientError: Error {
        case notConnected
        case noSession
        case handshakeFailed(String)
        case notPaired
    }

    private var connection: NWConnection?
    private var session: SessionCrypto?
    private var pendingHandshake: CheckedContinuation<Void, Error>?
    private(set) var state: ClientState = .idle
    private var stateContinuations: [AsyncStream<ClientState>.Continuation] = []

    func connect(to payload: PairingPayload) async throws {
        guard let pskData = payload.pskData else {
            throw ClientError.notPaired
        }
        if let existing = connection {
            existing.cancel()
        }
        update(state: .connecting)

        let endpoint = try await pickEndpoint(payload: payload)
        let conn = try await openConnection(to: endpoint)
        connection = conn
        try await runHandshake(psk: pskData)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        session = nil
        update(state: .idle)
    }

    func send(_ message: Message) async throws {
        guard let conn = connection, state == .connected else {
            throw ClientError.notConnected
        }
        guard var session = self.session else {
            throw ClientError.noSession
        }
        let frame = try session.seal(message)
        self.session = session
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(
            identifier: "uv-message",
            metadata: [metadata]
        )
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: frame, contentContext: context, isComplete: true, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            })
        }
    }

    func observe() -> AsyncStream<ClientState> {
        AsyncStream { continuation in
            stateContinuations.append(continuation)
            continuation.yield(state)
        }
    }

    // MARK: - Internals

    private func pickEndpoint(payload: PairingPayload) async throws -> NWEndpoint {
        if let hint = payload.hostHint, !hint.isEmpty {
            return NWEndpoint.hostPort(
                host: NWEndpoint.Host(hint),
                port: NWEndpoint.Port(rawValue: payload.port)!
            )
        }
        let browser = PeerBrowser()
        defer { browser.cancel() }
        return try await browser.resolve(deviceUUID: payload.deviceUUID, timeout: 3.0)
    }

    private func openConnection(to endpoint: NWEndpoint) async throws -> NWConnection {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        parameters.includePeerToPeer = true
        let conn = NWConnection(to: endpoint, using: parameters)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumer = ContinuationOnce(cont)
            conn.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }
                Task { await self.handleConnectionState(newState) }
                switch newState {
                case .ready:
                    resumer.resume(.success(()))
                case .failed(let err):
                    resumer.resume(.failure(err))
                case .cancelled:
                    resumer.resume(.failure(URLError(.cancelled)))
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
        return conn
    }

    private func handleConnectionState(_ networkState: NWConnection.State) {
        switch networkState {
        case .failed(let err):
            update(state: .failed(String(describing: err)))
        case .cancelled:
            update(state: .idle)
        default:
            break
        }
    }

    private func runHandshake(psk: Data) async throws {
        guard let conn = connection else { throw ClientError.notConnected }
        update(state: .handshaking)

        let clientSalt = SessionCrypto.freshSalt()
        let frame = HandshakeCodec.encode(HandshakeFrame(salt: clientSalt))
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(
            identifier: "uv-handshake",
            metadata: [metadata]
        )

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: frame, contentContext: context, isComplete: true, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            })
        }

        let response: Data = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let resumer = ContinuationOnce(cont)
            conn.receiveMessage { data, _, _, error in
                if let error {
                    resumer.resume(.failure(error))
                    return
                }
                guard let data, !data.isEmpty else {
                    resumer.resume(.failure(ClientError.handshakeFailed("empty response")))
                    return
                }
                resumer.resume(.success(data))
            }
        }

        let serverFrame: HandshakeFrame
        do {
            serverFrame = try HandshakeCodec.decode(response)
        } catch {
            throw ClientError.handshakeFailed(String(describing: error))
        }
        let key = SessionCrypto.deriveSessionKey(
            psk: psk,
            saltInitiator: clientSalt,
            saltResponder: serverFrame.salt
        )
        session = SessionCrypto(key: key, role: .initiator)
        update(state: .connected)
    }

    private func update(state: ClientState) {
        self.state = state
        for continuation in stateContinuations {
            continuation.yield(state)
        }
    }
}
