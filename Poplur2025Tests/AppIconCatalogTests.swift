import Testing
@testable import Poplur2025

struct AppIconCatalogTests {
    @Test func catalogUsesStableUniqueIdentifiers() {
        let icons = PoplurAppIcon.allCases
        #expect(icons.count == 4)
        #expect(Set(icons.map(\.rawValue)).count == icons.count)
        #expect(icons.first == .defaultClay)
        #expect(PoplurAppIcon.defaultClay.alternateIconName == nil)
    }

    @Test func everyAlternateNameRoundTrips() {
        for icon in PoplurAppIcon.allCases {
            #expect(PoplurAppIcon.resolve(alternateIconName: icon.alternateIconName) == icon)
            #expect(!icon.previewAssetName.isEmpty)
        }
    }
}
