import Foundation
import Darwin

enum PrimaryAddress {
    /// Best-effort: the first non-loopback IPv4 address on en0/en1/awdl0-style
    /// interfaces. Used as a hint in the QR payload so the iPhone has somewhere
    /// to start before falling back to Bonjour discovery.
    static func firstNonLoopbackIPv4() -> String? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            let addr = current.pointee.ifa_addr
            guard (flags & IFF_UP) != 0,
                  (flags & IFF_LOOPBACK) == 0,
                  let addr,
                  addr.pointee.sa_family == sa_family_t(AF_INET)
            else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let result = getnameinfo(
                addr, len,
                &hostname, socklen_t(hostname.count),
                nil, 0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let ip = String(cString: hostname)
                if !ip.isEmpty { return ip }
            }
        }
        return nil
    }
}
