//
//  PreviewServer.swift
//  bonchi-festival
//
//  Minimal HTTP/1.1 server that serves a live HTML status page on the local network.
//  Used by the projector-server mode to provide a URL-based preview of the game state,
//  accessible from any browser on the same Wi-Fi network (e.g., a Mac connected to a
//  projector).  The page auto-refreshes every 3 seconds and reflects the current game
//  state supplied by the `htmlProvider` closure.
//

import Foundation
import Network

// MARK: - PreviewServer

final class PreviewServer {

    /// The TCP port the server listens on.
    static let port: UInt16 = 8765

    /// Serial queue on which all network I/O runs.
    private let queue = DispatchQueue(label: "com.bonchi.preview-server", qos: .background)

    /// The active NWListener, or nil when the server is stopped.
    private var listener: NWListener?

    /// Called on each HTTP request to obtain the current HTML body.
    /// The closure is invoked on the background queue; the closure body is responsible
    /// for any necessary synchronisation.  For `GameManager.buildPreviewHTML()`, reads
    /// of Swift value types (`Int`, `Double`, `String`) are accepted without a lock
    /// because the preview page is a non-critical status display and minor tearing
    /// between fields is acceptable.
    var htmlProvider: (() -> String)?

    // MARK: - Public interface

    /// The URL at which the preview page can be reached, built from the device's
    /// current IPv4 address on en0.  Returns nil if the device has no Wi-Fi address.
    var previewURL: URL? {
        guard let ip = PreviewServer.localIPv4() else { return nil }
        return URL(string: "http://\(ip):\(Self.port)")
    }

    /// Start listening for incoming connections.  Calling start() while already
    /// running is safe — it is a no-op.
    func start() {
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: Self.port),
              let l = try? NWListener(using: .tcp, on: port) else { return }
        listener = l
        l.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        l.start(queue: queue)
    }

    /// Stop the server and release all resources.
    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        // Receive the HTTP request (we only need to know a request arrived;
        // we ignore method, path, and headers for this simple status server).
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard data != nil else { connection.cancel(); return }
            let html = self?.htmlProvider?() ?? "<p>Loading…</p>"
            let body = Data(html.utf8)
            let header = [
                "HTTP/1.1 200 OK",
                "Content-Type: text/html; charset=utf-8",
                "Content-Length: \(body.count)",
                "Connection: close",
                "",
                ""
            ].joined(separator: "\r\n")
            var response = Data(header.utf8)
            response.append(body)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    // MARK: - Networking helpers

    /// Returns the IPv4 address of the device's primary Wi-Fi interface (en0),
    /// or nil if the device is not connected to Wi-Fi.
    static func localIPv4() -> String? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr = ifaddrPtr
        while let ifa = ptr {
            let name = String(cString: ifa.pointee.ifa_name)
            guard let addr = ifa.pointee.ifa_addr else { ptr = ifa.pointee.ifa_next; continue }
            let family = addr.pointee.sa_family
            if name == "en0", family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    addr,
                    socklen_t(addr.pointee.sa_len),
                    &host, socklen_t(host.count),
                    nil, 0,
                    NI_NUMERICHOST
                )
                return String(cString: host)
            }
            ptr = ifa.pointee.ifa_next
        }
        return nil
    }
}
