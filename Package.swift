// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Fluxa",
    platforms: [
        // @Observable macro requires macOS 14; MenuBarExtra available since macOS 13.
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4")
    ],
    targets: [
        .executableTarget(
            name: "Fluxa",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Fluxa",
            exclude: ["Resources/Info.plist"],
            resources: [
                // fluxa.icns is the app/popover icon
                .copy("Resources/fluxa.icns"),
                // Vector switch mark for the menu bar, generated from new-icon.svg with
                // `rsvg-convert -f pdf -o Sources/Fluxa/Resources/menu-icon.pdf new-icon.svg`
                .copy("Resources/menu-icon.pdf"),
                // Agent marks (vendor logos) as vector PDFs, generated from the SVGs beside them
                .copy("Resources/AgentIcons")
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
                // build.sh preserves the complete vendor framework in Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
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
