import SwiftUI
import AppKit

// MARK: - FocusOnboardingView

/// One-time setup guide for Focus Mode.
/// Presented as a standalone Window (not a sheet) so it stays open when the user
/// switches to the Shortcuts app to create the shortcuts.
struct FocusOnboardingView: View {

    @Environment(PopoverViewModel.self) private var viewModel
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.fluxaVisualStyle) private var visualStyle

    private var isCyber: Bool { visualStyle != .classic }
    private var palette: ControlDeckPalette { .resolve(visualStyle) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(isCyber ? palette.gpu : Color.blue)
                        .frame(
                            width: isCyber ? 34 : nil,
                            height: isCyber ? 34 : nil
                        )
                        .background {
                            if isCyber {
                                FluxCutShape(cut: 9).fill(palette.gpu.opacity(0.12))
                            }
                        }
                        .overlay {
                            if isCyber {
                                FluxCutShape(cut: 9).stroke(palette.gpu.opacity(0.34), lineWidth: 1)
                            }
                        }
                    Text("Focus Mode Setup")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text("Fluxa needs two Shortcuts to toggle Focus Mode.\nFollow these steps — the window stays open while you work in Shortcuts.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(isCyber ? palette.module : Color.clear)

            pageDivider

            // MARK: Steps
            VStack(alignment: .leading, spacing: 0) {
                stepRow(number: 1) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open Shortcuts")
                                .font(.system(size: 12, weight: .medium))
                            Text("Tap the button to launch the Shortcuts app")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open Shortcuts") {
                            openShortcuts()
                        }
                        .buttonStyle(FluxaButtonStyle())
                    }
                }

                pageDivider.padding(.leading, 44)

                stepRow(number: 2) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Create the first shortcut")
                            .font(.system(size: 12, weight: .medium))
                        shortcutInstructionRow(
                            icon: "moon.fill",
                            name: FocusModeService.focusOnShortcutName,
                            description: "Action: \"Set Focus\" → set to Enable"
                        )
                    }
                }

                pageDivider.padding(.leading, 44)

                stepRow(number: 3) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Create the second shortcut")
                            .font(.system(size: 12, weight: .medium))
                        shortcutInstructionRow(
                            icon: "moon.zzz.fill",
                            name: FocusModeService.focusOffShortcutName,
                            description: "Action: \"Set Focus\" → set to Disable"
                        )
                    }
                }
            }

            pageDivider

            // MARK: Footer
            HStack(spacing: 10) {
                Spacer()

                Button("Cancel") {
                    dismissWindow(id: "focus-onboarding")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

                doneButton
            }
            .padding(16)
            .background(isCyber ? palette.recessed : Color.clear)
        }
        .frame(width: 380)
        .fluxaPanelSurface(classicBackground: Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Subviews

    private func stepRow<Content: View>(number: Int, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Step number badge
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background {
                    if isCyber {
                        FluxCutShape(cut: 6).fill(palette.brandGradient)
                    } else {
                        Circle().fill(Color.blue)
                    }
                }

            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func shortcutInstructionRow(icon: String, name: String, description: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isCyber ? palette.gpu : Color.blue)
                .frame(width: 26, height: 26)
                .background {
                    if isCyber {
                        FluxCutShape(cut: 6).fill(palette.gpu.opacity(0.11))
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.1))
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                // Shortcut name with copy button
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    CopyButton(text: name)
                }
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background {
            if isCyber {
                FluxCutShape(cut: 8).fill(palette.module)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06))
            }
        }
        .overlay {
            if isCyber {
                FluxCutShape(cut: 8).stroke(palette.border, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var pageDivider: some View {
        if isCyber {
            Rectangle()
                .fill(palette.border)
                .frame(height: 1)
        } else {
            Divider()
        }
    }

    @ViewBuilder
    private var doneButton: some View {
        if isCyber {
            Button("Done", action: completeSetup)
                .buttonStyle(FluxaPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        } else {
            Button("Done", action: completeSetup)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Actions

    private func openShortcuts() {
        // Try app URL first, fall back to bundle path
        let appURL = URL(fileURLWithPath: "/System/Applications/Shortcuts.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.openApplication(
                at: appURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        } else {
            // Fallback for non-standard installations
            NSWorkspace.shared.open(URL(string: "shortcuts://")!)
        }
    }

    private func completeSetup() {
        viewModel.completeFocusOnboarding()
        dismissWindow(id: "focus-onboarding")
    }
}

// MARK: - CopyButton

private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundStyle(copied ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .help("Copy name")
    }
}
