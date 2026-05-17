//
//  FeedViewHelper.swift
//  Helper Utilities for FeedView
//

import Foundation
import SwiftUI

// MARK: - Array Safe Subscript Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Notification Name Extensions


