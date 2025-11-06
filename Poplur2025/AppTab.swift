import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case map
    case record
    case feed
    case profile
    case settings

    var title: String {
        switch self {
        case .map: return "Map"
        case .record: return "Record"
        case .feed: return "Feed"
        case .profile: return "Profile"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .map: return "map"
        case .record: return "plus.circle.fill"
        case .feed: return "list.dash"
        case .profile: return "person.circle"
        case .settings: return "gearshape"
        }
    }
}
