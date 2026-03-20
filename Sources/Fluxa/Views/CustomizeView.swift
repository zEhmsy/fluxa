import SwiftUI

// MARK: - CustomizeView

/// Sheet that lets the user reorder, show/hide actions, and toggle subtitle visibility.
/// All changes are written through to AppSettings immediately (with UserDefaults persistence).
struct CustomizeView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(PopoverViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            HStack {
                Text("Customize Fluxa")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.blue)
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
                    Text("ACTIONS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                // MARK: Display Options
                Section {
                    Toggle("Show Subtitles", isOn: Binding(
                        get: { settings.showSubtitles },
                        set: { settings.showSubtitles = $0 }
                    ))
                    .font(.system(size: 13))
                } header: {
                    Text("DISPLAY")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
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
                } header: {
                    Text("SYSTEM")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
            // Note: editMode is iOS/tvOS only. On macOS, List with .onMove shows
            // drag handles automatically — no editMode needed.
        }
        .frame(width: 300, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - CustomizeRowView

/// A single row in the Customize list with drag handle, icon, name, and visibility toggle.
private struct CustomizeRowView: View {

    let action: QuickAction
    let settings: AppSettings

    private var isHidden: Bool {
        settings.hiddenActionIDs.contains(action.id)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.icon)
                .font(.system(size: 13))
                .foregroundStyle(isHidden ? .tertiary : .secondary)
                .frame(width: 20)

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
            .tint(.blue)
            .scaleEffect(0.8)
        }
    }
}
