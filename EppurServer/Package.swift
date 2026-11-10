// swift-tools-version: 6.0
//
// Eppur-Dienst: hält Spracherkennung (Parakeet TDT 0.6B v3 via FluidAudio)
// und Korrektur-LLM (Qwen 3.5 2B via MLX) dauerhaft im Speicher und bietet
// eine lokale HTTP-API auf 127.0.0.1 an.
//
// Bauen (Metal-Shader brauchen xcodebuild, nicht `swift build`):
//   ./install.sh
//

import PackageDescription

let package = Package(
    name: "EppurServer",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "eppur-server",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Kommandozeile: eppur list / search / transcribe / export / mcp
        .executableTarget(
            name: "eppur",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
