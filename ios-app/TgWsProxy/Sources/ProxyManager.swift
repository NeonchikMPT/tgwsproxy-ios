import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.tgwsproxy.app", category: "ProxyManager")

struct ProxyStats {
    var connectionsTotal: Int = 0
    var connectionsActive: Int = 0
    var connectionsWS: Int = 0
    var connectionsTCPFallback: Int = 0
    var connectionsBad: Int = 0
    var wsErrors: Int = 0
    var bytesUp: UInt64 = 0
    var bytesDown: UInt64 = 0
}

@MainActor
class ProxyManager: ObservableObject {
    static let shared = ProxyManager()

    @Published var isRunning = false
    @Published var stats = ProxyStats()
    @Published var config = ProxyConfig.load()

    private var server: MTProtoProxyServer?

    var tgLink: String {
        "tg://proxy?server=\(config.host)&port=\(config.port)&secret=dd\(config.secret)"
    }

    func startProxy() {
        guard !isRunning else { return }

        logger.info("Starting proxy on \(self.config.host):\(self.config.port)")

        server = MTProtoProxyServer(config: config, statsCallback: { [weak self] newStats in
            Task { @MainActor in
                self?.stats = newStats
            }
        })

        Task {
            do {
                try await server?.start()
                isRunning = true
                logger.info("Proxy started successfully")
            } catch {
                logger.error("Failed to start proxy: \(error)")
                isRunning = false
            }
        }
    }

    func stopProxy() {
        guard isRunning else { return }
        logger.info("Stopping proxy")
        server?.stop()
        server = nil
        isRunning = false
        stats = ProxyStats()
    }

    func saveConfig() {
        config.save()
        if isRunning {
            stopProxy()
            startProxy()
        }
    }
}
