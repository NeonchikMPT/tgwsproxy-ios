import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var proxy: ProxyManager
    @Environment(\.dismiss) private var dismiss

    @State private var host: String = ""
    @State private var port: String = ""
    @State private var secret: String = ""
    @State private var dcLines: String = ""
    @State private var bufferKB: String = ""
    @State private var poolSize: String = ""
    @State private var verbose: Bool = false
    @State private var showError: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Подключение MTProto") {
                    LabeledContent("IP-адрес") {
                        TextField("127.0.0.1", text: $host)
                            .multilineTextAlignment(.trailing)
                            .monospaced()
                    }
                    LabeledContent("Порт") {
                        TextField("1443", text: $port)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .monospaced()
                    }
                    HStack {
                        LabeledContent("Secret") {
                            TextField("hex secret", text: $secret)
                                .multilineTextAlignment(.trailing)
                                .monospaced()
                                .font(.system(.caption, design: .monospaced))
                        }
                        Button {
                            secret = ProxyConfig.generateSecret()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }

                Section("Датацентры (DC → IP)") {
                    TextEditor(text: $dcLines)
                        .frame(minHeight: 80)
                        .monospaced()
                        .font(.system(.caption, design: .monospaced))
                }

                Section("Производительность") {
                    LabeledContent("Буфер, КБ") {
                        TextField("256", text: $bufferKB)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .monospaced()
                    }
                    LabeledContent("Пул WS-сессий") {
                        TextField("4", text: $poolSize)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .monospaced()
                    }
                    Toggle("Подробные логи", isOn: $verbose)
                }

                if let error = showError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    HStack {
                        Text("Версия")
                        Spacer()
                        Text("1.4.0-ios")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { loadConfig() }
        }
    }

    private func loadConfig() {
        let cfg = proxy.config
        host = cfg.host
        port = "\(cfg.port)"
        secret = cfg.secret
        dcLines = cfg.dcRedirects.map { "\($0.key):\($0.value)" }.joined(separator: "\n")
        bufferKB = "\(cfg.bufferSizeKB)"
        poolSize = "\(cfg.poolSize)"
        verbose = cfg.verbose
    }

    private func save() {
        guard let portInt = UInt16(port), portInt > 0 else {
            showError = "Порт должен быть числом 1-65535"
            return
        }
        guard secret.count == 32, (try? UInt64(secret.prefix(16), radix: 16)) != nil else {
            showError = "Secret должен быть 32 hex-символа"
            return
        }

        var dcRedirects: [Int: String] = [:]
        for line in dcLines.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let dc = Int(parts[0]) else {
                showError = "Неверный формат DC: \(trimmed)"
                return
            }
            dcRedirects[dc] = String(parts[1])
        }

        var cfg = proxy.config
        cfg.host = host
        cfg.port = Int(portInt)
        cfg.secret = secret
        cfg.dcRedirects = dcRedirects
        cfg.bufferSizeKB = Int(bufferKB) ?? 256
        cfg.poolSize = Int(poolSize) ?? 4
        cfg.verbose = verbose

        proxy.config = cfg
        proxy.saveConfig()
        dismiss()
    }
}
