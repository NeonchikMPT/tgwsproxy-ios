# TG WS Proxy — iOS

Порт [tg-ws-proxy](https://github.com/Flowseal/tg-ws-proxy) на iOS.

MTProto WebSocket Bridge Proxy для Telegram, работающий прямо на iPhone.
Поднимает локальный MTProto прокси-сервер, который перенаправляет трафик
Telegram через WebSocket к серверам Telegram.

## Возможности

- Полный порт MTProto Obfuscated2 протокола на Swift
- WebSocket подключение к `kwsN.web.telegram.org` через TLS
- TCP fallback при недоступности WebSocket
- Re-encryption трафика (клиент ↔ прокси ↔ Telegram)
- Разделение пакетов (Message Splitter) для WS
- Dynamic Island / Live Activity для работы в фоне
- SwiftUI интерфейс с настройками
- Не требует Xcode для сборки IPA (GitHub Actions)

## Архитектура

```
Sources/
├── TgWsProxyApp.swift        — точка входа SwiftUI
├── ContentView.swift          — главный экран (старт/стоп, статистика)
├── SettingsView.swift         — настройки (порт, secret, DC)
├── ProxyConfig.swift          — конфигурация (UserDefaults)
├── ProxyManager.swift         — управление прокси-сервером
├── Crypto.swift               — AES-256-CTR, SHA-256 (CommonCrypto)
├── RawWebSocket.swift         — WebSocket клиент (NWConnection + TLS)
├── MTProtoHandshake.swift     — MTProto handshake, relay init, splitter
├── MTProtoProxyServer.swift   — TCP сервер (NWListener) + мост WS/TCP
└── LiveActivityManager.swift  — управление Dynamic Island

LiveActivity/
├── ProxyLiveActivity.swift    — виджет Dynamic Island
└── Info.plist                 — конфигурация расширения
```

## Сборка IPA

### Вариант 1: GitHub Actions (рекомендуется)

1. Скопируйте папку `ios-app/` в свой репозиторий
2. Запустите workflow `.github/workflows/build-ios.yml`
3. Скачайте артефакт `TgWsProxy-unsigned-ipa`
4. Подпишите IPA своим сертификатом разработчика

### Вариант 2: На Mac с Swift

```bash
cd ios-app
chmod +x build_ipa.sh
./build_ipa.sh
```

### Вариант 3: Локальная сборка IPA из скомпилированного бинарника

```bash
# После компиляции на Mac или CI:
python build_ipa_remote.py --binary path/to/TgWsProxy
```

## Подписание и установка

IPA создаётся **неподписанным**. Для установки нужно подписать:

### С помощью codesign (на Mac):
```bash
# Распаковать
unzip TgWsProxy-unsigned.ipa -d build/
# Подписать
codesign --force --sign "Apple Development: YOUR_ID" \
    --entitlements TgWsProxy/Resources/TgWsProxy.entitlements \
    build/Payload/TgWsProxy.app
# Запаковать обратно
cd build && zip -r ../TgWsProxy-signed.ipa Payload/
```

### С помощью Sideloadly / AltStore:
Просто перетащите IPA в программу — подпись произойдёт автоматически.

### С помощью ios-app-signer (Mac):
Откройте IPA, выберите свой сертификат и профиль.

## Использование

1. Запустите приложение на iPhone
2. Нажмите «Запустить» — прокси начнёт слушать на `127.0.0.1:1443`
3. В Telegram: Настройки → Данные и хранилище → Прокси → MTProto
   - Сервер: `127.0.0.1`
   - Порт: `1443`
   - Secret: показан в приложении (с префиксом `dd`)
4. Или нажмите «Открыть в Telegram» для автоматической настройки

## Фоновая работа

Приложение использует Live Activity / Dynamic Island для поддержания
фонового процесса. При запуске прокси создаётся Live Activity,
которая отображается на Dynamic Island и экране блокировки.

## Зависимости

Никаких внешних зависимостей. Используются только системные фреймворки:
- Foundation
- SwiftUI / UIKit
- Network (NWConnection, NWListener)
- CommonCrypto (AES, SHA256)
- ActivityKit (Live Activity)
- Security (SecRandomCopyBytes)

## Минимальные требования

- iOS 16.1+ (для Live Activity / Dynamic Island)
- iPhone с чипом A12+ (arm64)
