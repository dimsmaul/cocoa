// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Cocoa",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Cocoa", targets: ["CocoaApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "CocoaApp",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "CocoaAppTests",
            dependencies: ["CocoaApp"],
            path: "Tests"
        )
    ]
)
