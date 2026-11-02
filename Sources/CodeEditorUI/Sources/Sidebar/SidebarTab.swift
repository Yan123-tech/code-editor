import Foundation

/// Navigation mode for the app sidebar.
public enum SidebarTab: String, CaseIterable, Identifiable, Sendable {
    case files = "Files"
    case search = "Search"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .files: return "folder"
        case .search: return "magnifyingglass"
        }
    }
}
