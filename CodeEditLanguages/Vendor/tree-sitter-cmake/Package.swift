// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "TreeSitterCmake",
    products: [
        .library(name: "TreeSitterCmake", targets: ["TreeSitterCmake"])
    ],
    targets: [
        .target(
            name: "TreeSitterCmake",
            path: ".",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        )
    ],
    cLanguageStandard: .c11
)
