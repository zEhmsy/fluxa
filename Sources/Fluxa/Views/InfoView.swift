import AppKit
import SwiftUI

// MARK: - InfoView

/// In-popover About page: app identity, live public GitHub details, and a focused support callout.
struct InfoView: View {

    @Environment(PopoverViewModel.self) private var viewModel
    @Environment(\.fluxaVisualStyle) private var visualStyle

    let onDone: () -> Void

    private static let buyMeACoffeeURL = URL(string: "https://www.buymeacoffee.com/gturturro")!

    private static let appIcon: NSImage? = {
        guard let url = Bundle.fluxaResources.url(forResource: "fluxa", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    private var github: GitHubProfileService { viewModel.githubProfile }
    private var isCyber: Bool { visualStyle != .classic }
    private var palette: ControlDeckPalette { .resolve(visualStyle) }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 12) {
                    appCard
                    developerCard
                    supportCard
                    privacyNote
                }
                .padding(12)
            }
        }
        .frame(width: FluxaTheme.panelWidth, height: 560)
        .fluxaPanelSurface()
        .task {
            await github.load()
        }
    }

    // MARK: - Header

    private var header: some View {
        FluxaPageHeader(
            title: "About Fluxa",
            subtitle: "Open source · local first",
            systemImage: "info.circle.fill",
            tint: FluxaTheme.accent
        ) {
            Button("Done", action: onDone)
                .buttonStyle(FluxaPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - App identity

    private var appCard: some View {
        FluxaToolCard {
            HStack(spacing: 12) {
                Group {
                    if let icon = Self.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "bolt.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(FluxaTheme.accent)
                    }
                }
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Fluxa")
                        .font(.system(size: 17, weight: .semibold))
                    Text(versionText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("System controls, live hardware stats, and agent usage — one click away.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(version) · Build \(build)"
    }

    // MARK: - GitHub

    private var developerCard: some View {
        FluxaToolCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    avatar

                    VStack(alignment: .leading, spacing: 2) {
                        Text(github.profile?.name ?? "Giuseppe Turturro")
                            .font(.system(size: 13, weight: .semibold))
                        Text("@\(github.profile?.login ?? "zEhmsy")")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        Task { await github.load(force: true) }
                    } label: {
                        if github.isLoading {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .buttonStyle(FluxaButtonStyle())
                    .disabled(github.isLoading)
                    .help("Refresh public GitHub details")
                    .accessibilityLabel("Refresh public GitHub details")
                }

                Text(developerDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorMessage = github.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.exclamationmark")
                            .foregroundStyle(FluxaTheme.orange)
                        Text(errorMessage)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                } else if github.profile != nil || github.repository != nil {
                    githubStats
                } else {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Reading public GitHub details…")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    githubLink(
                        "Developer",
                        systemImage: "person.crop.circle",
                        destination: github.profile?.htmlURL ?? GitHubProfileService.profilePageURL
                    )
                    githubLink(
                        "Source code",
                        systemImage: "chevron.left.forwardslash.chevron.right",
                        destination: github.repository?.htmlURL ?? GitHubProfileService.repositoryPageURL
                    )
                }
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(isCyber ? palette.recessed : FluxaTheme.elevatedSurface)

            AsyncImage(url: github.profile?.avatarURL) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(FluxaTheme.accent)
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(isCyber ? palette.border : FluxaTheme.border, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private var developerDescription: String {
        github.profile?.bio
            ?? github.repository?.description
            ?? "Independent macOS developer building practical, privacy-minded tools in Swift."
    }

    private var githubStats: some View {
        HStack(spacing: 0) {
            githubStat(
                value: github.repository.map { String($0.stargazersCount) } ?? "—",
                label: "Stars",
                systemImage: "star.fill"
            )
            githubStat(
                value: github.profile.map { String($0.publicRepos) } ?? "—",
                label: "Repos",
                systemImage: "shippingbox.fill"
            )
            githubStat(
                value: github.profile.map { String($0.followers) } ?? "—",
                label: "Followers",
                systemImage: "person.2.fill"
            )
            githubStat(
                value: github.repository?.language ?? "Swift",
                label: "Language",
                systemImage: "swift"
            )
        }
        .padding(.vertical, 8)
        .fluxaModuleChrome(
            fill: isCyber ? palette.recessed : FluxaTheme.elevatedSurface,
            border: isCyber ? palette.border : FluxaTheme.border,
            cornerRadius: 9,
            cut: 8
        )
    }

    private func githubStat(value: String, label: String, systemImage: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(FluxaTheme.accent)
                Text(value)
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
            }
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func githubLink(_ title: String, systemImage: String, destination: URL) -> some View {
        Link(destination: destination) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(FluxaTheme.accent)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 27)
            .fluxaModuleChrome(
                fill: FluxaTheme.accent.opacity(0.10),
                border: FluxaTheme.accent.opacity(isCyber ? 0.32 : 0.20),
                cornerRadius: 7,
                cut: 6
            )
        }
        .buttonStyle(.plain)
        .help("Open \(title) on GitHub")
    }

    // MARK: - Support

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FluxaTheme.amber)
                    .frame(width: 34, height: 34)
                    .fluxaModuleChrome(
                        fill: FluxaTheme.brown.opacity(0.16),
                        border: FluxaTheme.brown.opacity(isCyber ? 0.34 : 0),
                        cornerRadius: 9,
                        cut: 8
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Enjoying Fluxa?")
                        .font(.system(size: 13, weight: .semibold))
                    Text("A coffee helps keep it free, focused, and actively maintained.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Link(destination: Self.buyMeACoffeeURL) {
                HStack(spacing: 7) {
                    Image(systemName: "heart.fill")
                    Text("Buy me a coffee")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background {
                    let gradient = LinearGradient(
                        colors: [FluxaTheme.brown, FluxaTheme.orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    if isCyber {
                        FluxCutShape(cut: 8).fill(gradient)
                    } else {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(gradient)
                    }
                }
                .overlay {
                    if isCyber {
                        FluxCutShape(cut: 8).stroke(.white.opacity(0.18), lineWidth: 1)
                    } else {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Support Giuseppe on Buy Me a Coffee")
            .accessibilityLabel("Buy Giuseppe a coffee")
        }
        .padding(14)
        .background {
            let gradient = LinearGradient(
                colors: [FluxaTheme.amber.opacity(0.10), FluxaTheme.brown.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if isCyber {
                FluxCutShape(cut: 12).fill(gradient)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(gradient)
            }
        }
        .overlay {
            if isCyber {
                FluxCutShape(cut: 12).stroke(FluxaTheme.brown.opacity(0.38), lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(FluxaTheme.brown.opacity(0.30), lineWidth: 1)
            }
        }
    }

    private var privacyNote: some View {
        Label("No ads · No analytics · Public GitHub data only", systemImage: "hand.raised.fill")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
            .padding(.bottom, 3)
            .accessibilityElement(children: .combine)
    }
}
