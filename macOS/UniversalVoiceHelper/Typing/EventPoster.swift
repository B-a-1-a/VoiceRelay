import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

final class EventPoster: @unchecked Sendable {
    enum DeliveryResult: Sendable {
        case typed
        case copiedToClipboardSecureInput
        case copiedToClipboardNoAccessibility
    }

    private let secondsPerCharacter: TimeInterval

    init(charactersPerSecond: Double = 600) {
        secondsPerCharacter = 1.0 / max(charactersPerSecond, 1)
    }

    @discardableResult
    func deliver(_ text: String) -> DeliveryResult {
        guard !text.isEmpty else { return .typed }

        if IsSecureEventInputEnabled() {
            copyToPasteboard(text)
            return .copiedToClipboardSecureInput
        }

        if !AXIsProcessTrusted() {
            copyToPasteboard(text)
            return .copiedToClipboardNoAccessibility
        }

        type(text)
        return .typed
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func type(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let chunkSize = 20
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            let chunk = String(text[index..<next])
            postChunk(chunk, source: source)
            index = next
        }
    }

    private func postChunk(_ chunk: String, source: CGEventSource?) {
        let utf16 = Array(chunk.utf16)
        utf16.withUnsafeBufferPointer { bufferPtr in
            guard let baseAddress = bufferPtr.baseAddress else { return }
            let downEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            downEvent?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: baseAddress)
            downEvent?.post(tap: .cghidEventTap)

            let upEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            upEvent?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: baseAddress)
            upEvent?.post(tap: .cghidEventTap)
        }
        let pause = secondsPerCharacter * Double(chunk.count)
        if pause > 0 {
            Thread.sleep(forTimeInterval: pause)
        }
    }
}
