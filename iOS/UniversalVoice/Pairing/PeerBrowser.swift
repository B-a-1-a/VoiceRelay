import Foundation
import Network
import UniversalVoiceProtocol

final class PeerBrowser: @unchecked Sendable {
    enum BrowseError: Error {
        case notFound
        case cancelled
        case browserFailed(String)
    }

    private let browser: NWBrowser

    init() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        browser = NWBrowser(
            for: .bonjour(type: BonjourService.type, domain: nil),
            using: parameters
        )
    }

    /// Find a peer whose mDNS TXT record contains the given device UUID.
    /// Returns the resolved endpoint or throws after the timeout.
    func resolve(deviceUUID: String, timeout: TimeInterval = 3.0) async throws -> NWEndpoint {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<NWEndpoint, Error>) in
            let resumer = BrowseContinuationOnce(cont)
            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    guard case let .bonjour(txt) = result.metadata else { continue }
                    if txt["uuid"] == deviceUUID {
                        resumer.resume(.success(result.endpoint))
                        return
                    }
                }
            }
            browser.stateUpdateHandler = { state in
                switch state {
                case .failed(let err):
                    resumer.resume(.failure(BrowseError.browserFailed(String(describing: err))))
                case .cancelled:
                    resumer.resume(.failure(BrowseError.cancelled))
                default:
                    break
                }
            }
            browser.start(queue: .global(qos: .userInitiated))

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                resumer.resume(.failure(BrowseError.notFound))
            }
        }
    }

    func cancel() {
        browser.cancel()
    }
}

private final class BrowseContinuationOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private let continuation: CheckedContinuation<NWEndpoint, Error>

    init(_ continuation: CheckedContinuation<NWEndpoint, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<NWEndpoint, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !fired else { return }
        fired = true
        switch result {
        case .success(let endpoint): continuation.resume(returning: endpoint)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}
