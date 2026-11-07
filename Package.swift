// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Vocal",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "VocalCore", targets: ["VocalCore"]),
        .library(name: "VocalRuntime", targets: ["VocalRuntime"])
    ],
    dependencies: [
        .package(url: "https://github.com/gradium-ai/xn-ptts.git", exact: "0.6.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.20")
    ],
    targets: [
        .target(name: "VocalCore"),
        .target(name: "VocalRuntime", dependencies: ["VocalCore",
            "LlamaFramework",
            .product(name: "ptts", package: "xn-ptts"),
            .product(name: "ZIPFoundation", package: "ZIPFoundation")]),
        .executableTarget(name: "VocalAppCheck", dependencies: ["VocalRuntime", "VocalCore"], path: "App",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "VocalEngineCheck", dependencies: ["VocalRuntime"], path: "Tests/VocalEngineCheck"),
        .executableTarget(name: "VocalCoreChecks", dependencies: ["VocalCore"], path: "Tests/VocalCoreTests"),
        .binaryTarget(name: "LlamaFramework",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b12018/llama-b12018-xcframework.zip",
            checksum: "c0c7daf1a710e1849a5b3c5a292e85ff5609d5dd3d64239eb3d23c76dcad03b3")
    ],
    swiftLanguageModes: [.v5]
)
