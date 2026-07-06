//
//  LookAroundState.swift
//  Poplur2025
//
//  State machine for the Street View (Apple MapKit Look Around) button/flow.
//

import Foundation
import MapKit

enum LookAroundState {
    case idle
    case noCoordinateSelected
    case checking
    case available(MKLookAroundScene)
    case unavailable
    case unsupported
    case error(String)

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    /// Text for the floating "Street View" button in its various states.
    var buttonLabel: String {
        switch self {
        case .idle, .noCoordinateSelected, .available, .unavailable:
            return "Street View"
        case .checking:
            return "Checking Street View…"
        case .unsupported:
            return "Street View"
        case .error:
            return "Street View"
        }
    }
}

extension LookAroundState: Equatable {
    static func == (lhs: LookAroundState, rhs: LookAroundState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.noCoordinateSelected, .noCoordinateSelected),
             (.checking, .checking),
             (.available, .available),
             (.unavailable, .unavailable),
             (.unsupported, .unsupported):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}
