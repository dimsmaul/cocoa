// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Cocoa",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Cocoa", targets: ["Cocoa"])
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
        .package(url: "https://github.com/danielsaidi/RichTextKit.git", from: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "Cocoa",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "RichTextKit", package: "RichTextKit")
            ],
            path: "Sources"
        )
    ]
)
