//
//  DemoPostStore.swift
//  Demo Post Store for Feed
//

import Foundation
import SwiftUI

// MARK: - Demo Post Store (shared in-memory database for demo users)

/// Singleton that stores all generated demo posts so they can be queried by userID
final class DemoPostStore {
    static let shared = DemoPostStore()
    private init() {}
    
    private var posts: [FeedPost] = []
    
    func store(_ posts: [FeedPost]) {
        // Add new posts, avoiding duplicates by ID
        var addedCount = 0
        for post in posts {
            if !self.posts.contains(where: { $0.id == post.id }) {
                self.posts.append(post)
                addedCount += 1
            }
        }
        print("📦 [DemoPostStore] Stored \(addedCount) new posts (total: \(self.posts.count))")
    }
    
    func posts(for userID: String) -> [FeedPost] {
        let userPosts = posts.filter { $0.userID == userID }
        print("👤 [DemoPostStore] Found \(userPosts.count) posts for userID: \(userID)")
        return userPosts
    }
    
    func allPosts() -> [FeedPost] {
        print("📚 [DemoPostStore] Total posts: \(posts.count)")
        return posts
    }
    
    // Add method to get all unique users
    func allUsers() -> Set<String> {
        let users = Set(posts.map { $0.userID })
        print("👥 [DemoPostStore] Total unique users: \(users.count)")
        return users
    }
}
