import Foundation
import Network
import os.log

private let logger = Logger(subsystem: "com.tgwsproxy.app", category: "RawWebSocket")

// MARK: - WebSocket Handshake Error

struct WsHandshakeError: Error {
    let statusCode: Int
    let statusLine: String
    let headers: [String: String]
    let location: String?

    var isRedirect: Bool {
        [301, 302, 303, 307, 308].contains(statusCode)
    }
}

// MARK: - Raw WebSocket (TLS, without URLSession — for raw binary framing)

actor RawWebSocket {
    private var connection: NWConnection?
    private var isClosed = false
    private var receiveBuffer = Data()

    static let opBinary: UInt8 = 0x2
    static let opClose: UInt8  = 0x8
    static let opPing: UInt8   = 0x9
    static let opPong: UInt8   = 0xA

    init() {}

    static func connect(ip: String, domain: String, path: String = "/apiws",
                        timeout: TimeInterval = 10.0) async throws -> RawWebSocket {
        let ws = RawWebSocket()
        try await ws.performConnect(ip: ip, domain: domain, path: path, timeout: timeout)
        return ws
    }

    private func performConnect(ip: String, domain: String, path: String,
                                timeout: TimeInterval) async throws {
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_peer_domain(tlsOptions.securityProtocolOptions, domain)
        // Allow self-signed / mismatched for Telegram's WS endpoints
        sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { _, _, completionHandler in
            completionHandler(true)
        }, DispatchQueue.global())

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.connectionTimeout = Int(timeout)

        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: NWEndpoint.Port(rawValue: 443)!)
        let conn = NWConnection(to: endpoint, using: params)

        self.connection = conn

        // Wait for connection ready
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.stateUpdateHandler = nil
                    cont.resume()
                case .failed(let error):
                    conn.stateUpdateHandler = nil
                    cont.resume(throwing: error)
                case .cancelled:
                    conn.stateUpdateHandler = nil
                    cont.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            conn.start(queue: DispatchQueue.global())
        }

        // Send HTTP upgrade request
        let wsKeyBytes = secureRandomBytes(16)
        let wsKey = Data(wsKeyBytes).base64EncodedString()

        let request = [
            "GET \(path) HTTP/1.1",
            "Host: \(domain)",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: \(wsKey)",
            "Sec-WebSocket-Version: 13",
            "Sec-WebSocket-Protocol: binary",
            "Origin: https://web.telegram.org",
            "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "",
            ""
        ].joined(separator: "\r\n")

        let requestData = request.data(using: .utf8)!
        try await sendRaw(requestData)

        // Read HTTP response
        let responseData = try await receiveRaw(maxLength: 4096, timeout: timeout)
        guard let responseStr = String(data: responseData, encoding: .utf8) else {
            throw WsHandshakeError(statusCode: 0, statusLine: "invalid response", headers: [:], location: nil)
        }

        let lines = responseStr.components(separatedBy: "\r\n")
        guard !lines.isEmpty else {
            throw WsHandshakeError(statusCode: 0, statusLine: "empty response", headers: [:], location: nil)
        }

        let parts = lines[0].split(separator: " ", maxSplits: 2)
        let statusCode = parts.count >= 2 ? Int(parts[1]) ?? 0 : 0

        if statusCode == 101 {
            // Find end of headers, keep any remaining data in buffer
            if let headerEnd = responseData.range(of: Data("\r\n\r\n".utf8)) {
                let remaining = responseData.suffix(from: headerEnd.upperBound)
                if !remaining.isEmpty {
                    receiveBuffer.append(remaining)
                }
            }
            return
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonIdx = line.firstIndex(of: ":") {
                let key = line[line.startIndex..<colonIdx].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        conn.cancel()
        throw WsHandshakeError(statusCode: statusCode, statusLine: lines[0],
                                headers: headers, location: headers["location"])
    }

    // MARK: - Send

    func send(_ data: Data) async throws {
        guard !isClosed else { throw ConnectionError.closed }
        let frame = buildFrame(opcode: Self.opBinary, data: data, mask: true)
        try await sendRaw(frame)
    }

    func sendBatch(_ parts: [Data]) async throws {
        guard !isClosed else { throw ConnectionError.closed }
        var combined = Data()
        for part in parts {
            combined.append(buildFrame(opcode: Self.opBinary, data: part, mask: true))
        }
        try await sendRaw(combined)
    }

    // MARK: - Receive

    func recv() async throws -> Data? {
        while !isClosed {
            let (opcode, payload) = try await readFrame()

            switch opcode {
            case Self.opClose:
                isClosed = true
                let closeFrame = buildFrame(opcode: Self.opClose,
                                            data: payload.prefix(2), mask: true)
                try? await sendRaw(closeFrame)
                return nil

            case Self.opPing:
                let pongFrame = buildFrame(opcode: Self.opPong, data: payload, mask: true)
                try? await sendRaw(pongFrame)
                continue

            case Self.opPong:
                continue

            case 0x1, 0x2:
                return payload

            default:
                continue
            }
        }
        return nil
    }

    // MARK: - Close

    func close() async {
        guard !isClosed else { return }
        isClosed = true
        let closeFrame = buildFrame(opcode: Self.opClose, data: Data(), mask: true)
        try? await sendRaw(closeFrame)
        connection?.cancel()
    }

    // MARK: - Low-level I/O

    private func sendRaw(_ data: Data) async throws {
        guard let conn = connection else { throw ConnectionError.closed }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }
    }

    private func receiveRaw(maxLength: Int, timeout: TimeInterval = 10) async throws -> Data {
        guard let conn = connection else { throw ConnectionError.closed }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: maxLength) { data, _, _, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let data {
                    cont.resume(returning: data)
                } else {
                    cont.resume(throwing: ConnectionError.closed)
                }
            }
        }
    }

    private func receiveExactly(_ count: Int) async throws -> Data {
        while receiveBuffer.count < count {
            let chunk = try await receiveRaw(maxLength: 65536)
            receiveBuffer.append(chunk)
        }
        let result = receiveBuffer.prefix(count)
        receiveBuffer.removeFirst(count)
        return Data(result)
    }

    // MARK: - WebSocket framing

    private func buildFrame(opcode: UInt8, data: Data, mask: Bool) -> Data {
        var frame = Data()
        let fb: UInt8 = 0x80 | opcode
        let length = data.count

        if mask {
            let maskKey = Data(secureRandomBytes(4))
            if length < 126 {
                frame.append(fb)
                frame.append(UInt8(0x80 | length))
            } else if length < 65536 {
                frame.append(fb)
                frame.append(UInt8(0x80 | 126))
                frame.append(UInt8((length >> 8) & 0xFF))
                frame.append(UInt8(length & 0xFF))
            } else {
                frame.append(fb)
                frame.append(UInt8(0x80 | 127))
                for i in stride(from: 56, through: 0, by: -8) {
                    frame.append(UInt8((length >> i) & 0xFF))
                }
            }
            frame.append(maskKey)
            // XOR mask
            var masked = Data(count: data.count)
            for i in 0..<data.count {
                masked[i] = data[i] ^ maskKey[i % 4]
            }
            frame.append(masked)
        } else {
            if length < 126 {
                frame.append(fb)
                frame.append(UInt8(length))
            } else if length < 65536 {
                frame.append(fb)
                frame.append(126)
                frame.append(UInt8((length >> 8) & 0xFF))
                frame.append(UInt8(length & 0xFF))
            } else {
                frame.append(fb)
                frame.append(127)
                for i in stride(from: 56, through: 0, by: -8) {
                    frame.append(UInt8((length >> i) & 0xFF))
                }
            }
            frame.append(data)
        }
        return frame
    }

    private func readFrame() async throws -> (UInt8, Data) {
        let hdr = try await receiveExactly(2)
        let opcode = hdr[0] & 0x0F
        var length = UInt64(hdr[1] & 0x7F)

        if length == 126 {
            let ext = try await receiveExactly(2)
            length = UInt64(ext[0]) << 8 | UInt64(ext[1])
        } else if length == 127 {
            let ext = try await receiveExactly(8)
            length = 0
            for i in 0..<8 {
                length = (length << 8) | UInt64(ext[i])
            }
        }

        let hasMask = (hdr[1] & 0x80) != 0
        if hasMask {
            let maskKey = try await receiveExactly(4)
            var payload = try await receiveExactly(Int(length))
            for i in 0..<payload.count {
                payload[i] ^= maskKey[i % 4]
            }
            return (opcode, payload)
        }

        let payload = try await receiveExactly(Int(length))
        return (opcode, payload)
    }

    enum ConnectionError: Error {
        case closed
        case timeout
    }
}
