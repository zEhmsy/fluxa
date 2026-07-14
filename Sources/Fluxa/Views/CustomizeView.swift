import SwiftUI

// MARK: - CustomizeView

/// Sheet that lets the user reorder, show/hide actions, and toggle subtitle visibility.
/// All changes are written through to AppSettings immediately (with UserDefaults persistence).
struct CustomizeView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(PopoverViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Customize")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Drag to reorder, switch to show or hide")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Close via the sheet's own binding — NOT @Environment(\.dismiss):
                // inside a MenuBarExtra window that DismissAction dismisses the
                // whole popover window instead of just the sheet.
                Button("Done") { viewModel.isShowingCustomize = false }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.blue)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // MARK: Action List (reorderable + togglable)
            List {
                Section {
                    ForEach(settings.actionOrder, id: \.self) { id in
                        if let action = ActionCatalog.action(for: id) {
                            CustomizeRowView(action: action, settings: settings)
                        }
                    }
                    .onMove { from, to in
                        settings.actionOrder.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    sectionHeader("ACTIONS")
                }

                // MARK: Display Options
                Section {
                    Toggle("Show Subtitles", isOn: Binding(
                        get: { settings.showSubtitles },
                        set: { settings.showSubtitles = $0 }
                    ))
                    .font(.system(size: 13))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(.blue)
                } header: {
                    sectionHeader("DISPLAY")
                }

                // MARK: System
                Section {
                    Toggle("Launch at Login", isOn: Binding(
                        get: { viewModel.launchAtLogin.isEnabled },
                        set: { enabled in
                            try? viewModel.launchAtLogin.setEnabled(enabled)
                        }
                    ))
                    .font(.system(size: 13))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(.blue)
                } header: {
                    sectionHeader("SYSTEM")
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            // Note: editMode is iOS/tvOS only. On macOS, List with .onMove shows
            // drag handles automatically — no editMode needed.
        }
        .frame(width: 320, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - CustomizeRowView

/// A single row in the Customize list with tinted icon tile, name, and visibility switch.
private struct CustomizeRowView: View {

    let action: QuickAction
    let settings: AppSettings

    private var isHidden: Bool {
        settings.hiddenActionIDs.contains(action.id)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHidden ? .secondary : action.tint)
                .frame(width: 24, height: 24)
                .background(
                    (isHidden ? Color.secondary.opacity(0.08) : action.tint.opacity(0.13)),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )

            Text(action.title)
                .font(.system(size: 13))
                .foregroundStyle(isHidden ? .secondary : .primary)

            Spacer()

            Toggle("", isOn: Binding(
                get: { !isHidden },
                set: { visible in
                    if visible {
                        settings.hiddenActionIDs.remove(action.id)
                    } else {
                        settings.hiddenActionIDs.insert(action.id)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(action.tint)
        }
        .padding(.vertical, 1)
    }
}
