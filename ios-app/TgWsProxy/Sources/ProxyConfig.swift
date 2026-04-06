import Foundation
import Security

struct ProxyConfig: Codable {
    var host: String = "127.0.0.1"
    var port: Int = 1443
    var secret: String = ProxyConfig.generateSecret()
    var dcRedirects: [Int: String] = [2: "149.154.167.220", 4: "149.154.167.220"]
    var dcOverrides: [Int: Int] = [203: 2]
    var bufferSizeKB: Int = 256
    var poolSize: Int = 4
    var verbose: Bool = false

    var bufferSize: Int { bufferSizeKB * 1024 }

    static func generateSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static let dcDefaultIPs: [Int: String] = [
        1: "149.154.175.50",
        2: "149.154.167.51",
        3: "149.154.175.100",
        4: "149.154.167.91",
        5: "149.154.171.5",
        203: "91.105.192.100"
    ]

    static func load() -> ProxyConfig {
        guard let data = UserDefaults.standard.data(forKey: "proxyConfig"),
              let config = try? JSONDecoder().decode(ProxyConfig.self, from: data) else {
            return ProxyConfig()
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "proxyConfig")
        }
    }
}
