import Foundation
import ActivityKit

// MARK: - Live Activity Attributes

struct ProxyActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var isRunning: Bool
        var connectionsActive: Int
        var bytesUp: UInt64
        var bytesDown: UInt64
    }

    var host: String
    var port: Int
}

// MARK: - Live Activity Manager

@MainActor
class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    private var activity: Activity<ProxyActivityAttributes>?

    func startActivity(host: String, port: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = ProxyActivityAttributes(host: host, port: port)
        let state = ProxyActivityAttributes.ContentState(
            isRunning: true, connectionsActive: 0, bytesUp: 0, bytesDown: 0
        )

        do {
            let content = ActivityContent(state: state, staleDate: nil)
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    func updateActivity(connections: Int, bytesUp: UInt64, bytesDown: UInt64) {
        let state = ProxyActivityAttributes.ContentState(
            isRunning: true, connectionsActive: connections,
            bytesUp: bytesUp, bytesDown: bytesDown
        )
        Task {
            let content = ActivityContent(state: state, staleDate: nil)
            await activity?.update(content)
        }
    }

    func stopActivity() {
        let state = ProxyActivityAttributes.ContentState(
            isRunning: false, connectionsActive: 0, bytesUp: 0, bytesDown: 0
        )
        Task {
            let content = ActivityContent(state: state, staleDate: nil)
            await activity?.end(content, dismissalPolicy: .immediate)
            activity = nil
        }
    }
}
