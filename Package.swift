// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JLUGate",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "JLUGateCore", targets: ["JLUGateCore"]),
        .library(name: "JLUGateNet", targets: ["JLUGateNet"]),
        .executable(name: "jlugate-probe", targets: ["jlugate-probe"]),
    ],
    targets: [
        .target(name: "JLUGateCore"),
        .target(name: "JLUGateNet", dependencies: ["JLUGateCore"]),
        .executableTarget(name: "jlugate-probe", dependencies: ["JLUGateCore", "JLUGateNet"]),
        // App 的真正产物由 App/project.yml（XcodeGen）构建；这个 target 只是让
        // `swift build` / CI 顺带编译一遍 SwiftUI 源码，避免 UI 层悄悄坏掉。
        .executableTarget(name: "AppCompileCheck",
                          dependencies: ["JLUGateCore", "JLUGateNet"],
                          path: "App/Sources"),
        .testTarget(name: "JLUGateCoreTests", dependencies: ["JLUGateCore"]),
        .testTarget(name: "JLUGateNetTests", dependencies: ["JLUGateNet", "JLUGateCore"]),
    ],
    swiftLanguageModes: [.v6]
)
