// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Fluxa",
    platforms: [
        // @Observable macro requires macOS 14; MenuBarExtra available since macOS 13.
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Fluxa",
            path: "Sources/Fluxa",
            exclude: ["Resources/Info.plist"],
            resources: [
                // fluxa.icns is loaded at runtime for the menu bar icon
                .copy("Resources/fluxa.icns")
            ],
            // Note: SPM forbids Info.plist as a top-level resource.
            // Instead it is embedded directly into the binary's __TEXT,__info_plist section
            // via the linker flags below. macOS reads it from there at runtime.
            swiftSettings: [
                // Required so @main works correctly in an SPM executable target
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ServiceManagement"),
                // Embed Info.plist into the binary so LSUIElement / NSPrincipalClass etc. are found
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Fluxa/Resources/Info.plist"
                ]),
            ]
        )
    ]
)
