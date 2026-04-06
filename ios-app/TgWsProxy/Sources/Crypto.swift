import Foundation
import CommonCrypto
import Security

// MARK: - AES-256-CTR Cipher

final class AESCTR {
    private var key: [UInt8]
    private var counter: [UInt8]             // 16-byte big-endian counter (= IV)
    private var keystreamBuffer: [UInt8] = []
    private var keystreamOffset: Int = 0

    init(key: [UInt8], iv: [UInt8]) {
        precondition(key.count == 32, "AES-256 key must be 32 bytes")
        precondition(iv.count == 16, "IV must be 16 bytes")
        self.key = key
        self.counter = iv
    }

    func process(_ data: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: data.count)
        var offset = 0

        while offset < data.count {
            if keystreamOffset >= keystreamBuffer.count {
                keystreamBuffer = encryptBlock(counter)
                keystreamOffset = 0
                incrementCounter()
            }

            let available = keystreamBuffer.count - keystreamOffset
            let needed = data.count - offset
            let chunk = min(available, needed)

            for i in 0..<chunk {
                out[offset + i] = data[offset + i] ^ keystreamBuffer[keystreamOffset + i]
            }
            offset += chunk
            keystreamOffset += chunk
        }
        return out
    }

    func process(_ data: Data) -> Data {
        Data(process([UInt8](data)))
    }

    private func encryptBlock(_ block: [UInt8]) -> [UInt8] {
        var encrypted = [UInt8](repeating: 0, count: block.count + kCCBlockSizeAES128)
        var numBytesEncrypted: size_t = 0

        let status = CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionECBMode),
            key, key.count,
            nil,
            block, block.count,
            &encrypted, encrypted.count,
            &numBytesEncrypted
        )
        precondition(status == kCCSuccess, "AES ECB encrypt failed: \(status)")
        return Array(encrypted.prefix(16))
    }

    private func incrementCounter() {
        for i in stride(from: 15, through: 0, by: -1) {
            counter[i] &+= 1
            if counter[i] != 0 { break }
        }
    }
}

// MARK: - SHA-256

func sha256(_ data: [UInt8]) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CC_SHA256(data, CC_LONG(data.count), &hash)
    return hash
}

// MARK: - Random bytes

func secureRandomBytes(_ count: Int) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: count)
    _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
    return bytes
}
