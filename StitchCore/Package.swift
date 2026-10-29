// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StitchCore",
    platforms: [
        // App 最低部署 iOS 16（任务书硬约束）。
        // macOS 仅作为本地 swift test 的构建宿主（CoreGraphics/ImageIO 在 macOS 同样可用），
        // 不意味着 App 跑 macOS。
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "StitchCore", targets: ["StitchCore"])
    ],
    targets: [
        .target(name: "StitchCore"),
        .testTarget(name: "StitchCoreTests", dependencies: ["StitchCore"]),
        .testTarget(name: "OverlapAdvisorTests", dependencies: ["StitchCore"])
    ]
)
