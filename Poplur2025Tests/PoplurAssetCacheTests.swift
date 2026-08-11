import Foundation
import Testing
@testable import Poplur2025

struct PoplurAssetCacheTests {
    private final class Token: NSObject {}

    private func limits(
        bytes: Int = 20,
        items: Int = 2,
        modelItems: Int = 2,
        textureItems: Int = 2
    ) -> PoplurAssetCache.Limits {
        PoplurAssetCache.Limits(
            byteLimit: bytes,
            itemLimit: items,
            categoryItemLimits: [
                .model: modelItems,
                .texture: textureItems,
                .scene: items,
                .decodedImage: items,
                .temporary: items,
                .video: items,
            ]
        )
    }

    @Test func evictsTheLeastRecentlyUsedEntryBeforeExceedingTheBudget() {
        let cache = PoplurAssetCache(limits: limits())
        #expect(cache.insert(Token(), forKey: "a", category: .model, estimatedByteCost: 10))
        #expect(cache.insert(Token(), forKey: "b", category: .model, estimatedByteCost: 10))
        let retainedA: Token? = cache.asset(forKey: "a", category: .model)
        #expect(retainedA != nil)

        #expect(cache.insert(Token(), forKey: "c", category: .model, estimatedByteCost: 10))
        let evictedB: Token? = cache.asset(forKey: "b", category: .model)
        let retainedC: Token? = cache.asset(forKey: "c", category: .model)
        #expect(evictedB == nil)
        #expect(retainedC != nil)
        #expect(cache.snapshot().estimatedByteCount == 20)
        #expect(cache.snapshot().itemCount == 2)
    }

    @Test func refusesAnEntryThatCanNeverFit() {
        let cache = PoplurAssetCache(limits: limits(bytes: 8, items: 2))
        #expect(!cache.insert(Token(), forKey: "oversized", category: .model, estimatedByteCost: 9))
        #expect(cache.snapshot().itemCount == 0)
        #expect(cache.snapshot().rejectionCount == 1)
    }

    @Test func categoryPressureDoesNotEvictAnUnrelatedCategory() {
        let cache = PoplurAssetCache(limits: limits(bytes: 30, items: 3, modelItems: 1, textureItems: 2))
        #expect(cache.insert(Token(), forKey: "texture", category: .texture, estimatedByteCost: 10))
        #expect(cache.insert(Token(), forKey: "old-model", category: .model, estimatedByteCost: 10))
        #expect(cache.insert(Token(), forKey: "new-model", category: .model, estimatedByteCost: 10))

        let texture: Token? = cache.asset(forKey: "texture", category: .texture)
        let oldModel: Token? = cache.asset(forKey: "old-model", category: .model)
        let newModel: Token? = cache.asset(forKey: "new-model", category: .model)
        #expect(texture != nil)
        #expect(oldModel == nil)
        #expect(newModel != nil)
        #expect(cache.snapshot().categoryCounts[.model] == 1)
    }
}
