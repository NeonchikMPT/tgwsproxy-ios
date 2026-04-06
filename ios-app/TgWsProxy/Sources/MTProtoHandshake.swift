import Foundation
import os.log

private let logger = Logger(subsystem: "com.tgwsproxy.app", category: "MTProto")

// MARK: - Constants

let HANDSHAKE_LEN = 64
let SKIP_LEN = 8
let PREKEY_LEN = 32
let KEY_LEN = 32
let IV_LEN = 16
let PROTO_TAG_POS = 56
let DC_IDX_POS = 60

let PROTO_TAG_ABRIDGED:     [UInt8] = [0xEF, 0xEF, 0xEF, 0xEF]
let PROTO_TAG_INTERMEDIATE: [UInt8] = [0xEE, 0xEE, 0xEE, 0xEE]
let PROTO_TAG_SECURE:       [UInt8] = [0xDD, 0xDD, 0xDD, 0xDD]

let PROTO_ABRIDGED_INT:            UInt32 = 0xEFEFEFEF
let PROTO_INTERMEDIATE_INT:        UInt32 = 0xEEEEEEEE
let PROTO_PADDED_INTERMEDIATE_INT: UInt32 = 0xDDDDDDDD

let RESERVED_FIRST_BYTES: Set<UInt8> = [0xEF]
let RESERVED_STARTS: Set<[UInt8]> = [
    [0x48, 0x45, 0x41, 0x44],  // HEAD
    [0x50, 0x4F, 0x53, 0x54],  // POST
    [0x47, 0x45, 0x54, 0x20],  // GET
    [0xEE, 0xEE, 0xEE, 0xEE],
    [0xDD, 0xDD, 0xDD, 0xDD],
    [0x16, 0x03, 0x01, 0x02],
]
let RESERVED_CONTINUE: [UInt8] = [0x00, 0x00, 0x00, 0x00]

let ZERO_64 = [UInt8](repeating: 0, count: 64)

// MARK: - Handshake

struct HandshakeResult {
    let dcId: Int
    let isMedia: Bool
    let protoTag: [UInt8]
    let protoInt: UInt32
    let clientDecPrekeyIV: [UInt8]  // 48 bytes: prekey(32) + iv(16)
}

func tryHandshake(_ handshake: [UInt8], secret: [UInt8]) -> HandshakeResult? {
    guard handshake.count == HANDSHAKE_LEN else { return nil }

    let decPrekeyAndIV = Array(handshake[SKIP_LEN ..< SKIP_LEN + PREKEY_LEN + IV_LEN])
    let decPrekey = Array(decPrekeyAndIV[0..<PREKEY_LEN])
    let decIV = Array(decPrekeyAndIV[PREKEY_LEN...])

    let decKey = sha256(decPrekey + secret)

    let decryptor = AESCTR(key: decKey, iv: decIV)
    let decrypted = decryptor.process(handshake)

    let protoTag = Array(decrypted[PROTO_TAG_POS ..< PROTO_TAG_POS + 4])

    guard protoTag == PROTO_TAG_ABRIDGED ||
          protoTag == PROTO_TAG_INTERMEDIATE ||
          protoTag == PROTO_TAG_SECURE else {
        return nil
    }

    // DC index: signed 16-bit little-endian at position 60
    let dcIdx = Int(Int16(littleEndian: decrypted.withUnsafeBufferPointer { buf in
        buf.baseAddress!.advanced(by: DC_IDX_POS).withMemoryRebound(to: Int16.self, capacity: 1) { $0.pointee }
    }))

    let dcId = abs(dcIdx)
    let isMedia = dcIdx < 0

    let protoInt: UInt32
    if protoTag == PROTO_TAG_ABRIDGED {
        protoInt = PROTO_ABRIDGED_INT
    } else if protoTag == PROTO_TAG_INTERMEDIATE {
        protoInt = PROTO_INTERMEDIATE_INT
    } else {
        protoInt = PROTO_PADDED_INTERMEDIATE_INT
    }

    return HandshakeResult(
        dcId: dcId, isMedia: isMedia,
        protoTag: protoTag, protoInt: protoInt,
        clientDecPrekeyIV: decPrekeyAndIV
    )
}

// MARK: - Generate relay init

func generateRelayInit(protoTag: [UInt8], dcIdx: Int) -> [UInt8] {
    while true {
        var rnd = secureRandomBytes(HANDSHAKE_LEN)

        if RESERVED_FIRST_BYTES.contains(rnd[0]) { continue }
        if RESERVED_STARTS.contains(Array(rnd[0..<4])) { continue }
        if Array(rnd[4..<8]) == RESERVED_CONTINUE { continue }

        let encKey = Array(rnd[SKIP_LEN ..< SKIP_LEN + PREKEY_LEN])
        let encIV = Array(rnd[SKIP_LEN + PREKEY_LEN ..< SKIP_LEN + PREKEY_LEN + IV_LEN])

        let encryptor = AESCTR(key: encKey, iv: encIV)

        // DC index as signed 16-bit little-endian
        let dcBytes: [UInt8] = withUnsafeBytes(of: Int16(dcIdx).littleEndian) { Array($0) }
        let tailPlain = protoTag + dcBytes + secureRandomBytes(2)

        let encryptedFull = encryptor.process(rnd)
        var keystreamTail = [UInt8](repeating: 0, count: 8)
        for i in 0..<8 {
            keystreamTail[i] = encryptedFull[56 + i] ^ rnd[56 + i]
        }

        var encryptedTail = [UInt8](repeating: 0, count: 8)
        for i in 0..<8 {
            encryptedTail[i] = tailPlain[i] ^ keystreamTail[i]
        }

        rnd[PROTO_TAG_POS..<HANDSHAKE_LEN] = ArraySlice(encryptedTail)
        return rnd
    }
}

// MARK: - WS domains

func wsDomains(dc: Int, isMedia: Bool, overrides: [Int: Int]) -> [String] {
    let effectiveDC = overrides[dc] ?? dc
    if isMedia {
        return ["kws\(effectiveDC)-1.web.telegram.org", "kws\(effectiveDC).web.telegram.org"]
    }
    return ["kws\(effectiveDC).web.telegram.org", "kws\(effectiveDC)-1.web.telegram.org"]
}

// MARK: - Message Splitter

class MsgSplitter {
    private var dec: AESCTR
    private var proto: UInt32
    private var cipherBuf = Data()
    private var plainBuf = Data()
    private var disabled = false

    init(relayInit: [UInt8], protoInt: UInt32) {
        let key = Array(relayInit[8..<40])
        let iv = Array(relayInit[40..<56])
        self.dec = AESCTR(key: key, iv: iv)
        _ = self.dec.process(ZERO_64)  // skip first 64 bytes
        self.proto = protoInt
    }

    func split(_ chunk: Data) -> [Data] {
        if chunk.isEmpty { return [] }
        if disabled { return [chunk] }

        cipherBuf.append(chunk)
        plainBuf.append(Data(dec.process([UInt8](chunk))))

        var parts: [Data] = []
        while !cipherBuf.isEmpty {
            guard let packetLen = nextPacketLen() else { break }
            if packetLen <= 0 {
                parts.append(cipherBuf)
                cipherBuf.removeAll()
                plainBuf.removeAll()
                disabled = true
                break
            }
            parts.append(cipherBuf.prefix(packetLen))
            cipherBuf.removeFirst(packetLen)
            plainBuf.removeFirst(packetLen)
        }
        return parts
    }

    func flush() -> [Data] {
        if cipherBuf.isEmpty { return [] }
        let tail = cipherBuf
        cipherBuf.removeAll()
        plainBuf.removeAll()
        return [tail]
    }

    private func nextPacketLen() -> Int? {
        if plainBuf.isEmpty { return nil }
        if proto == PROTO_ABRIDGED_INT {
            return nextAbridgedLen()
        }
        if proto == PROTO_INTERMEDIATE_INT || proto == PROTO_PADDED_INTERMEDIATE_INT {
            return nextIntermediateLen()
        }
        return 0
    }

    private func nextAbridgedLen() -> Int? {
        let first = plainBuf[plainBuf.startIndex]
        let payloadLen: Int
        let headerLen: Int
        if first == 0x7F || first == 0xFF {
            if plainBuf.count < 4 { return nil }
            payloadLen = (Int(plainBuf[plainBuf.startIndex + 1]) |
                         (Int(plainBuf[plainBuf.startIndex + 2]) << 8) |
                         (Int(plainBuf[plainBuf.startIndex + 3]) << 16)) * 4
            headerLen = 4
        } else {
            payloadLen = Int(first & 0x7F) * 4
            headerLen = 1
        }
        if payloadLen <= 0 { return 0 }
        let packetLen = headerLen + payloadLen
        if plainBuf.count < packetLen { return nil }
        return packetLen
    }

    private func nextIntermediateLen() -> Int? {
        if plainBuf.count < 4 { return nil }
        let payloadLen = Int(plainBuf.withUnsafeBytes { buf in
            buf.load(as: UInt32.self)
        }.littleEndian) & 0x7FFFFFFF
        if payloadLen <= 0 { return 0 }
        let packetLen = 4 + payloadLen
        if plainBuf.count < packetLen { return nil }
        return packetLen
    }
}
