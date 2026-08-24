import ClipstackCore
import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case clipboard
    case pinned
    case emoji
    case kaomoji
    case symbols

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .clipboard: "doc.on.clipboard"
        case .pinned:    "pin.fill"
        case .emoji:     "face.smiling"
        case .kaomoji:   "ellipsis.bubble"
        case .symbols:   "textformat"
        }
    }

    var title: String {
        switch self {
        case .clipboard: "Clipboard"
        case .pinned:    "Pinned"
        case .emoji:     "Emoji"
        case .kaomoji:   "Kaomoji"
        case .symbols:   "Symbols"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    let onSelectItem: (ClipboardItem) -> Void
    let onInsertText: (String) -> Void

    @State private var tab: PanelTab = ProcessInfo.processInfo.environment["CLIPSTACK_DEBUG_TAB"]
        .flatMap(PanelTab.init(rawValue:)) ?? .clipboard
    @Namespace private var tabNamespace

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(selection: $tab, namespace: tabNamespace)

            Divider().opacity(0.5)

            if let error = model.storageError {
                Banner(
                    icon: "exclamationmark.triangle.fill",
                    title: "History won't be saved",
                    message: error,
                    tint: .orange
                )
            }

            if model.installLocation.blocksPermissions {
                Banner(
                    icon: "arrow.down.app.fill",
                    title: model.installLocation == .diskImage
                        ? "Move Clipstack to Applications"
                        : "Clipstack is running from a temporary copy",
                    message: model.installLocation == .diskImage
                        ? "You are running it from the disk image. Drag it to your Applications folder, then open it from there — permissions cannot be saved from here."
                        : "Move Clipstack to your Applications folder and open it again, so macOS can remember its permissions.",
                    tint: .orange,
                    action: ("Open Applications", {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
                    })
                )
            } else if model.needsAccessibility {
                Banner(
                    icon: "exclamationmark.circle.fill",
                    title: "Copied — press Cmd+V to paste",
                    message: "Allow Accessibility to paste automatically.",
                    tint: .orange,
                    action: ("Open Settings", AccessibilityPermission.openSettings)
                )
            }

            content
                // Crossfade rather than slide: the tabs are peers, so there is
                // no direction that would mean anything.
                .transition(.opacity)
                .animation(Theme.quick, value: tab)

            // Only the list tabs support arrow-key navigation; showing the hints
            // on the pickers would promise behaviour that is not there.
            if tab == .clipboard || tab == .pinned {
                KeyHintBar()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The panel's titlebar is hidden and its buttons are removed, but
        // SwiftUI still reserves safe area for it — about 28pt of dead space
        // above the tab strip, on a window only 500pt tall.
        .ignoresSafeArea(.container, edges: .top)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Theme.surfaceTint)
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .clipboard:
            ClipboardTabView(onSelect: onSelectItem)
        case .pinned:
            PinnedTabView(onSelect: onSelectItem)
        case .emoji:
            EmojiTabView(onSelect: onInsertText)
        case .kaomoji:
            GlyphTabView(
                title: "Kaomoji",
                categories: Catalogues.kaomoji,
                kind: .kaomoji,
                wideCells: true,
                onSelect: onInsertText
            )
        case .symbols:
            GlyphTabView(
                title: "Symbols",
                categories: Catalogues.symbols,
                kind: .symbols,
                wideCells: false,
                onSelect: onInsertText
            )
        }
    }
}

// MARK: - Tab strip

private struct TabStrip: View {
    @Binding var selection: PanelTab
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: Theme.Space.xxs) {
            ForEach(Array(PanelTab.allCases.enumerated()), id: \.element) { index, tab in
                TabButton(tab: tab, isSelected: selection == tab, namespace: namespace) {
                    withAnimation(Theme.spring) { selection = tab }
                }
                .keyboardShortcut(
                    KeyEquivalent(Character("\(index + 1)")),
                    modifiers: .command
                )
            }
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.top, Theme.Space.sm)
        .padding(.bottom, Theme.Space.xs)
    }
}

private struct TabButton: View {
    let tab: PanelTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Space.xs) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .foregroundStyle(iconStyle)

                // The indicator is one view moved between tabs, so it slides
                // rather than blinking out and in.
                ZStack {
                    Capsule().fill(.clear).frame(height: 2)

                    if isSelected {
                        Capsule()
                            .fill(Theme.accentGradient)
                            .frame(height: 2)
                            .matchedGeometryEffect(id: "tabIndicator", in: namespace)
                            .shadow(color: Theme.accentStart.opacity(0.6), radius: 4)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(isHovered && !isSelected ? Theme.cardHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in
            withAnimation(Theme.quick) { isHovered = hovering }
        }
        .help("\(tab.title) (⌘\(tabIndex))")
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var tabIndex: Int {
        (PanelTab.allCases.firstIndex(of: tab) ?? 0) + 1
    }

    private var iconStyle: AnyShapeStyle {
        isSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.secondary)
    }
}

// MARK: - Banner

/// Inline notice. Never blocks the panel — the content below stays usable.
private struct Banner: View {
    let icon: String
    let title: String
    let message: String
    let tint: Color
    var action: (title: String, perform: () -> Void)?

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if let action {
                GhostButton(title: action.title, action: action.perform)
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }
}
