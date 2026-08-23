import ClipstackCore
import SwiftUI

// MARK: - Search field

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    var focus: FocusState<Bool>.Binding?
    var onSubmit: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            field

            if !text.isEmpty {
                Button {
                    withAnimation(Theme.quick) { text = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel("Clear search")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .frame(height: 28)
        .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .hairline(Theme.Radius.md)
    }

    @ViewBuilder
    private var field: some View {
        let base = TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .onSubmit { onSubmit?() }

        if let focus {
            base.focused(focus)
        } else {
            base
        }
    }
}

// MARK: - Headers and empty states

struct PanelHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.top, Theme.Space.md)
        .padding(.bottom, Theme.Space.sm)
    }
}

/// Small text button used for header actions like "Clear all".
struct GhostButton: View {
    let title: String
    var role: ButtonRole?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(role == .destructive ? Theme.danger : Color.secondary)
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, Theme.Space.xs)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(isHovered ? Theme.cardHover : .clear)
                )
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in
            withAnimation(Theme.quick) { isHovered = hovering }
        }
    }
}

/// Inline confirmation strip.
///
/// Used in place of `confirmationDialog` because a sheet steals key focus from
/// the panel, which is set to dismiss when it loses focus. Confirming in place
/// also keeps a lightweight floating panel from throwing up a system modal.
struct ConfirmBar: View {
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.danger)

            Text(message)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            GhostButton(title: "Cancel", action: onCancel)

            Button(action: onConfirm) {
                Text(confirmTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, Theme.Space.xs)
                    .background(Theme.danger, in: Capsule())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.danger.opacity(0.12))
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var action: (title: String, perform: () -> Void)?

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.accentWash)
                    .frame(width: 56, height: 56)
                    .blur(radius: 8)

                Image(systemName: icon)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.accentGradient)
            }
            .accessibilityHidden(true)

            VStack(spacing: Theme.Space.xs) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.xl)
            }

            if let action {
                Button(action: action.perform) {
                    Text(action.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Space.lg)
                        .padding(.vertical, Theme.Space.sm)
                        .background(Theme.accentGradient, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .padding(.top, Theme.Space.xs)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Clipboard row

/// One history entry. Shared by the Clipboard and Pinned tabs.
///
/// Layout follows the native list convention — leading icon, title, dimmer
/// metadata line, trailing actions — so it reads like a Mail or Finder row
/// rather than a bespoke card.
struct ClipboardRow: View {
    let item: ClipboardItem
    let thumbnail: NSImage?
    let isSelected: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var showsActions: Bool { isHovered || isSelected }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: Theme.Space.sm) {
                leading

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12))
                        .lineLimit(item.kind == .image ? 1 : 2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)

                    metadata
                }

                Spacer(minLength: 0)
                actions
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .hairline(Theme.Radius.md, color: isSelected ? Theme.accentStart.opacity(0.55) : Theme.border)
            // Glow only on the selected row, so the eye has a single anchor.
            .shadow(color: isSelected ? Theme.accentStart.opacity(0.25) : .clear, radius: 8, y: 2)
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in
            withAnimation(Theme.quick) { isHovered = hovering }
        }
        .contextMenu {
            Button(item.pinned ? "Unpin" : "Pin", action: onTogglePin)
            Button("Delete", role: .destructive, action: onDelete)
        }
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Activate to paste")
    }

    // MARK: Content

    /// Images are their own best label, so the dimensions become the title and
    /// the picture carries the meaning.
    private var title: String {
        guard item.kind == .image else { return item.preview }
        guard let size = thumbnail?.pixelSize else { return "Image" }
        return "\(Int(size.width)) × \(Int(size.height))"
    }

    @ViewBuilder
    private var leading: some View {
        if item.kind == .image, let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 62, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                .hairline(Theme.Radius.sm)
                .accessibilityHidden(true)
        } else if let icon = SourceApp.icon(for: item.sourceBundleID) {
            // The originating app's own icon: more informative than a generic
            // document glyph, and instantly familiar.
            Image(nsImage: icon)
                .resizable()
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
        } else {
            Image(systemName: item.kind == .richText ? "textformat" : "text.alignleft")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var metadata: some View {
        Text(metadataText)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// "TextEdit · 28m ago" — source first, because it is the stronger cue when
    /// scanning for a clip you remember copying from somewhere specific.
    private var metadataText: String {
        let age = Self.timestamp.localizedString(for: item.createdAt, relativeTo: Date())

        if let source = SourceApp.name(for: item.sourceBundleID) {
            return "\(source) · \(age)"
        }
        return age
    }

    private var accessibilityText: String {
        item.kind == .image ? "Image, \(title), \(metadataText)" : "\(item.preview), \(metadataText)"
    }

    @ViewBuilder
    private var background: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            .fill(isHovered ? Theme.cardHover : Theme.card)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.accentWash)
                }
            }
    }

    private var actions: some View {
        HStack(spacing: Theme.Space.xxs) {
            // Pinned rows keep their pin visible; the rest reveal controls on
            // hover so the list stays calm.
            if showsActions || item.pinned {
                RowAction(
                    icon: item.pinned ? "pin.fill" : "pin",
                    tint: item.pinned ? Theme.pinned : .secondary,
                    label: item.pinned ? "Unpin" : "Pin",
                    action: onTogglePin
                )
            }

            if showsActions {
                RowAction(icon: "trash", tint: .secondary, hoverTint: Theme.danger, label: "Delete", action: onDelete)
            }
        }
        .transition(.opacity)
    }

    private static let timestamp: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

/// Footer showing the keyboard shortcuts for the list tabs.
///
/// Keyboard navigation is otherwise invisible — a hint bar is how Spotlight and
/// Raycast make it discoverable without a help screen.
struct KeyHintBar: View {
    var body: some View {
        HStack(spacing: Theme.Space.md) {
            hint(keys: ["\u{2191}", "\u{2193}"], label: "Navigate")
            hint(keys: ["\u{21A9}"], label: "Paste")
            hint(keys: ["\u{238B}"], label: "Close")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.06))
        .overlay(alignment: .top) { Divider().opacity(0.5) }
        // Decorative: the same actions are reachable by clicking, and VoiceOver
        // announces the real controls.
        .accessibilityHidden(true)
    }

    private func hint(keys: [String], label: String) -> some View {
        HStack(spacing: Theme.Space.xs) {
            HStack(spacing: 2) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 9, weight: .semibold))
                        .frame(minWidth: 16, minHeight: 15)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Theme.card)
                        )
                        .hairline(4)
                }
            }

            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

/// Icon button inside a row. Its hit area is padded well beyond the glyph.
struct RowAction: View {
    let icon: String
    var tint: Color = .secondary
    var hoverTint: Color?
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isHovered ? (hoverTint ?? tint) : tint)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(isHovered ? Theme.cardHover : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .onHover { hovering in
            withAnimation(Theme.quick) { isHovered = hovering }
        }
        .help(label)
        .accessibilityLabel(label)
    }
}
