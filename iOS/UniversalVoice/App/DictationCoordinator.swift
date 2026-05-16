import Foundation
import ActivityKit
import os

/// Bridges App Intents → DictationSession.
///
/// The App Intent runs in (or returns to) the app process. The session is owned
/// by the SwiftUI scene. We need a stable singleton that both ends can talk to.
@MainActor
final class DictationCoordinator {
    static let shared = DictationCoordinator()

    private(set) weak var session: DictationSession?
    private var darwinObserver: CFRunLoopObserver?
    private var darwinCallbackInstalled = false

    private init() {
        installStopObserver()
    }

    func register(session: DictationSession) {
        self.session = session
    }

    func requestStart() {
        if let session {
            Task { await session.start() }
        } else {
            // Session not yet attached; defer briefly.
            Task {
                for _ in 0..<10 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if let session = self.session {
                        await session.start()
                        return
                    }
                }
            }
        }
    }

    func requestStop() {
        guard let session else { return }
        Task { await session.stop() }
    }

    private func installStopObserver() {
        guard !darwinCallbackInstalled else { return }
        darwinCallbackInstalled = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = AppGroup.stopRequestDarwinNotification as CFString
        let unmanaged = Unmanaged.passUnretained(self)
        CFNotificationCenterAddObserver(
            center,
            unmanaged.toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let coordinator = Unmanaged<DictationCoordinator>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in coordinator.requestStop() }
            },
            name,
            nil,
            .deliverImmediately
        )
    }
}
