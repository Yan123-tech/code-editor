import CodeEditorCore
import CodeEditorThemes
import SwiftUI

// MARK: - New item kinds

/// What the create flows can add to a directory.
public enum NewItemKind: String {
    case file
    case folder

    var title: String {
        switch self {
        case .file: "New File"
        case .folder: "New Folder"
        }
    }

    var placeholder: String {
        switch self {
        case .file: "File name"
        case .folder: "Folder name"
        }
    }

    var iconName: String {
        switch self {
        case .file: "doc.badge.plus"
        case .folder: "folder.badge.plus"
        }
    }
}

/// A creation the user has requested but not yet named.
///
/// Owned by `AppState` so the toolbar's create menu and the sidebar's context menu
/// funnel into one sheet presentation.
public struct PendingCreation: Identifiable {
    public let id = UUID()
    public let kind: NewItemKind
    public let directory: URL

    public init(kind: NewItemKind, directory: URL) {
        self.kind = kind
        self.directory = directory
    }
}

// MARK: - Sheets

/// Sheet for naming a new file or folder. Grouped form, default action on Return.
public struct NewItemSheetView: View {
    let pending: PendingCreation
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    public init(pending: PendingCreation, onCreate: @escaping (String) -> Void) {
        self.pending = pending
        self.onCreate = onCreate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(pending.kind.title)
                .font(.headline)
                .padding(.bottom, Metrics.Space.relaxed)

            Form {
                TextField(pending.kind.placeholder, text: $name)
                    .onSubmit(submit)
            }
            .formStyle(.grouped)

            HStack {
                Text(pending.directory.path)
                    .font(Typography.hint)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(pending.directory.path)

                Spacer()

                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
            .padding(.top, Metrics.Space.regular)
        }
        .padding(Metrics.Space.loose)
        .frame(width: 380)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed)
        dismiss()
    }
}

/// Sheet for renaming an existing item.
struct RenameSheetView: View {
    let current: String
    let onRename: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(current: String, onRename: @escaping (String) -> Void) {
        self.current = current
        self.onRename = onRename
        _name = State(initialValue: current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Rename “\(current)”")
                .font(.headline)
                .padding(.bottom, Metrics.Space.relaxed)

            Form {
                TextField("New name", text: $name)
                    .onSubmit(submit)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Rename", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == current)
            }
            .padding(.top, Metrics.Space.regular)
        }
        .padding(Metrics.Space.loose)
        .frame(width: 380)
    }

    private func submit() {
        onRename(name)
        dismiss()
    }
}
