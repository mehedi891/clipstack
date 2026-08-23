import ClipstackCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isConfirmingReset = false
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ClipboardStore

    var body: some View {
        Form {
            Section {
                Toggle("Save clipboard history", isOn: Binding(
                    get: { settings.historyEnabled },
                    set: { model.setHistoryEnabled($0) }
                ))
                .help("When off, nothing new is recorded. Existing entries are kept.")

                LabeledContent("Keep") {
                    HStack(spacing: 8) {
                        Stepper(
                            value: Binding(
                                get: { settings.capacity },
                                set: { model.setCapacity($0) }
                            ),
                            in: AppSettings.capacityRange,
                            step: 10
                        ) {
                            Text("\(settings.capacity) items")
                                .monospacedDigit()
                        }
                    }
                }
                .help("Pinned entries are kept regardless of this limit.")
            } header: {
                Text("History")
            }

            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }

            Section {
                LabeledContent("Open the panel") {
                    HStack(spacing: 8) {
                        HotkeyRecorder(combo: Binding(
                            get: { settings.hotkey },
                            set: { settings.hotkey = $0 }
                        ))
                        .frame(width: 120, height: 22)

                        if settings.hotkey != .commandShiftV {
                            Button("Reset") { settings.hotkey = .commandShiftV }
                                .controlSize(.small)
                        }
                    }
                }
                .help("Click, then press the keys you want. At least one modifier is required.")

                if !model.hotkeyRegistered {
                    Label(
                        "Another app already owns this shortcut. Pick a different one.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                }
            } header: {
                Text("Shortcut")
            }

            Section {
                LabeledContent("Automatic paste") {
                    if model.accessibilityGranted {
                        Label("Working", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not working", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if !model.accessibilityGranted {
                    Button("Open Accessibility Settings") {
                        AccessibilityPermission.openSettings()
                    }
                }

                LabeledContent("Permission stuck?") {
                    Button("Reset Permission", role: .destructive) {
                        isConfirmingReset = true
                    }
                }
                .help("Clears macOS's saved permission for Clipstack so you can grant it again.")

                if let outcome = model.resetOutcome {
                    resetResult(outcome)
                }

                Text(
                    """
                    If the switch is already on but pasting still does nothing, \
                    macOS is probably holding more than one saved permission for \
                    Clipstack. Resetting clears them so you can add it once, cleanly.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Paste")
            }

            Section {
                HStack {
                    Text("\(store.items.count) stored")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear history") { store.clearAll(keepPinned: false) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.refreshAccessibilityState() }
        // A normal window, so a system dialog is safe here — unlike the panel,
        // which dismisses itself when it loses focus.
        .confirmationDialog(
            "Reset the Accessibility permission?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                model.resetAccessibilityPermission()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clipstack will be removed from the Accessibility list. You will need to add it again with the + button, which opens automatically.")
        }
    }

    /// Plain-language feedback, including the record count — more than one is
    /// itself the explanation for a permission that would not stick.
    @ViewBuilder
    private func resetResult(_ outcome: AccessibilityPermission.ResetOutcome) -> some View {
        switch outcome {
        case .cleared(let records) where records > 1:
            Label(
                "Cleared \(records) conflicting permissions. That was the problem. Add Clipstack again with +.",
                systemImage: "checkmark.circle.fill"
            )
            .font(.callout)
            .foregroundStyle(.green)

        case .cleared:
            Label("Permission cleared. Add Clipstack again with the + button.", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)

        case .nothingToClear:
            Label("Nothing was saved. Add Clipstack with the + button.", systemImage: "info.circle.fill")
                .font(.callout)
                .foregroundStyle(.secondary)

        case .failed(let message):
            Label("Could not reset: \(message)", systemImage: "xmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }
}
