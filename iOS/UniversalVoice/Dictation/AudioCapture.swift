import Foundation
@preconcurrency import AVFoundation
import os

final class AudioCapture: @unchecked Sendable {
    enum CaptureError: Error {
        case engineFailed(Error)
        case alreadyRunning
        case converterUnavailable
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let engine = AVAudioEngine()

    private struct State {
        var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
        var converter: AVAudioConverter?
        var targetFormat: AVAudioFormat?
        var isRunning = false
    }

    func start(outputFormat: AVAudioFormat) throws -> AsyncStream<AVAudioPCMBuffer> {
        let alreadyRunning = lock.withLock { $0.isRunning }
        guard !alreadyRunning else { throw CaptureError.alreadyRunning }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: [])

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        let newConverter: AVAudioConverter?
        if inputFormat.sampleRate != outputFormat.sampleRate
            || inputFormat.channelCount != outputFormat.channelCount
            || inputFormat.commonFormat != outputFormat.commonFormat {
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                throw CaptureError.converterUnavailable
            }
            newConverter = converter
        } else {
            newConverter = nil
        }

        lock.withLock { state in
            state.converter = newConverter
            state.targetFormat = outputFormat
        }
        let stream = AsyncStream<AVAudioPCMBuffer>(bufferingPolicy: .unbounded) { continuation in
            self.lock.withLock { state in
                state.continuation = continuation
            }
        }

        let bufferSize: AVAudioFrameCount = 4096
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            lock.withLock { state in
                state.continuation?.finish()
                state.continuation = nil
            }
            throw CaptureError.engineFailed(error)
        }
        lock.withLock { $0.isRunning = true }
        return stream
    }

    func stop() {
        let wasRunning = lock.withLock { state -> Bool in
            let was = state.isRunning
            state.isRunning = false
            return was
        }
        guard wasRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.withLock { state in
            state.continuation?.finish()
            state.continuation = nil
            state.converter = nil
            state.targetFormat = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func handle(buffer: AVAudioPCMBuffer) {
        let snapshot = lock.withLock { state -> (AsyncStream<AVAudioPCMBuffer>.Continuation?, AVAudioConverter?, AVAudioFormat?) in
            (state.continuation, state.converter, state.targetFormat)
        }
        guard let continuation = snapshot.0 else { return }
        if let converter = snapshot.1, let target = snapshot.2 {
            let ratio = target.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var fed = false
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, statusPtr in
                if fed {
                    statusPtr.pointee = .noDataNow
                    return nil
                }
                fed = true
                statusPtr.pointee = .haveData
                return buffer
            }
            if status == .haveData {
                continuation.yield(out)
            }
        } else {
            continuation.yield(buffer)
        }
    }
}
