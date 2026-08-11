//
//  DemoPostStore.swift
//  Demo Post Store for Feed
//

import Foundation
import SwiftUI

// MARK: - Demo Post Store (shared in-memory database for demo users)

/// Singleton that stores all generated demo posts so they can be queried by userID
final class DemoPostStore: @unchecked Sendable {
    static let shared = DemoPostStore()

    /// This store lives for the process lifetime, so it must never mirror an
    /// unbounded feed. Oldest posts are evicted in insertion order.
    private static let maximumPostCount = 512
    private let lock = NSLock()
    private var postRing: [FeedPost?]
    private var oldestPostIndex = 0
    private var postCount = 0
    private var postIDs = Set<String>()

    private init() {
        postRing = Array(repeating: nil, count: Self.maximumPostCount)
    }
    
    func store(_ newPosts: [FeedPost]) {
        lock.lock()
        defer { lock.unlock() }

        // Add new posts, avoiding duplicates by ID
        var addedCount = 0
        for post in newPosts where !postIDs.contains(post.id) {
            let insertionIndex: Int
            if postCount == Self.maximumPostCount {
                insertionIndex = oldestPostIndex
                if let evicted = postRing[insertionIndex] {
                    postIDs.remove(evicted.id)
                }
                oldestPostIndex = (oldestPostIndex + 1) % Self.maximumPostCount
            } else {
                insertionIndex = (oldestPostIndex + postCount) % Self.maximumPostCount
                postCount += 1
            }
            postRing[insertionIndex] = post
            postIDs.insert(post.id)
            addedCount += 1
        }
        print("📦 [DemoPostStore] Stored \(addedCount) new posts (total: \(postCount))")
    }
    
    func posts(for userID: String) -> [FeedPost] {
        lock.lock()
        defer { lock.unlock() }
        let userPosts = orderedPosts().filter { $0.userID == userID }
        print("👤 [DemoPostStore] Found \(userPosts.count) posts for userID: \(userID)")
        return userPosts
    }
    
    func allPosts() -> [FeedPost] {
        lock.lock()
        defer { lock.unlock() }
        let posts = orderedPosts()
        print("📚 [DemoPostStore] Total posts: \(posts.count)")
        return posts
    }
    
    // Add method to get all unique users
    func allUsers() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        let users = Set(orderedPosts().map { $0.userID })
        print("👥 [DemoPostStore] Total unique users: \(users.count)")
        return users
    }

    func purge() {
        lock.lock()
        defer { lock.unlock() }
        postRing = Array(repeating: nil, count: Self.maximumPostCount)
        oldestPostIndex = 0
        postCount = 0
        postIDs.removeAll(keepingCapacity: false)
    }

    /// Caller must hold `lock`.
    private func orderedPosts() -> [FeedPost] {
        guard postCount > 0 else { return [] }
        return (0..<postCount).compactMap { offset in
            postRing[(oldestPostIndex + offset) % Self.maximumPostCount]
        }
    }
}
