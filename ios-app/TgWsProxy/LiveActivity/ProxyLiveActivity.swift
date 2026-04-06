import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Live Activity Widget for Dynamic Island

@available(iOS 16.1, *)
struct ProxyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProxyActivityAttributes.self) { context in
            // Lock Screen banner
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    Label("TG Proxy", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isRunning ? "Active" : "Stopped")
                        .font(.caption2)
                        .foregroundStyle(context.state.isRunning ? .green : .red)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connections")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("\(context.state.connectionsActive)")
                                .font(.system(.body, design: .monospaced).bold())
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("↑ Upload")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(formatBytes(context.state.bytesUp))
                                .font(.system(.caption, design: .monospaced))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("↓ Download")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(formatBytes(context.state.bytesDown))
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.cyan)
                    .font(.caption2)
            } compactTrailing: {
                Text("\(context.state.connectionsActive)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.green)
            } minimal: {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.cyan)
                    .font(.caption2)
            }
        }
    }

    private func lockScreenView(context: ActivityViewContext<ProxyActivityAttributes>) -> some View {
        HStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(.cyan)

            VStack(alignment: .leading, spacing: 2) {
                Text("TG WS Proxy")
                    .font(.headline)
                Text("\(context.attributes.host):\(context.attributes.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(context.state.isRunning ? "●" : "○")
                    .foregroundStyle(context.state.isRunning ? .green : .red)
                Text("\(context.state.connectionsActive) conn")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        for unit in units {
            if value < 1024 { return String(format: "%.1f%@", value, unit) }
            value /= 1024
        }
        return String(format: "%.1fTB", value)
    }
}

// MARK: - Widget Bundle

@main
struct ProxyWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            ProxyLiveActivity()
        }
    }
}
