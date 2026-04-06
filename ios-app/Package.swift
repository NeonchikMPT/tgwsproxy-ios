// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TgWsProxy",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .executable(name: "TgWsProxy", targets: ["TgWsProxy"]),
    ],
    targets: [
        .executableTarget(
            name: "TgWsProxy",
            path: "TgWsProxy/Sources",
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Network"),
                .linkedFramework("ActivityKit"),
                .linkedFramework("WidgetKit"),
            ]
        ),
    ]
)
