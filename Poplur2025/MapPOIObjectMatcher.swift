//
//  MapPOIObjectMatcher.swift
//  Poplur2025
//
//  Matches a real map point-of-interest to the 3D popular object that fits it, so the
//  map pops the *appropriate* object over the *exact* location (e.g. a basketball arena
//  pops a basketball). Category → object channel, then the POI's name is scanned for a
//  more specific object (e.g. "…Basketball…" → sports_basketball).
//

import MapKit

enum MapPOIObjectMatcher {

    /// Returns the (channelId, objectId) to pop over a POI, or nil if the POI isn't a
    /// content-worthy location (gas stations, ATMs, parking, etc. get nothing).
    static func match(for item: MKMapItem) -> (channelId: String, objectId: String)? {
        let name = (item.name ?? "").lowercased()

        // A keyword in the name can override the coarse category (e.g. a "Basketball Club"
        // filed under a generic category still pops a basketball).
        let channel = channel(forName: name) ?? channel(for: item.pointOfInterestCategory)
        guard let channel else { return nil }

        let objectId = PopularObjectCatalog.specificObject(nameHint: name, channelId: channel)
            ?? PopularObjectCatalog.representative(for: channel)
        return (channel, objectId)
    }

    // MARK: - Category → channel

    private static func channel(for category: MKPointOfInterestCategory?) -> String? {
        guard let category else { return nil }
        switch category {
        // Sports (iOS 18 sport-specific + venues)
        case .stadium, .basketball, .baseball, .soccer, .tennis, .golf, .goKart,
             .bowling, .miniGolf, .skating, .skiing, .surfing, .swimming, .fishing,
             .rockClimbing, .kayaking, .hiking:
            return "sports"
        // Fitness
        case .fitnessCenter, .spa:
            return "fitness"
        // Food & drink
        case .restaurant, .bakery, .brewery, .cafe, .distillery, .foodMarket, .winery:
            return "food"
        // Fashion / shopping / beauty
        case .store:
            return "fashion"
        case .beauty:
            return "beauty"
        // Music / nightlife
        case .musicVenue, .nightlife:
            return "music"
        // Creative / cultural venues
        case .museum, .theater, .movieTheater, .planetarium, .aquarium, .zoo,
             .conventionCenter, .fairground, .amusementPark:
            return "modelling"
        // Travel / civic landmarks → news (globe/newspaper family)
        case .airport, .publicTransport, .library, .school, .university, .hotel,
             .landmark, .castle, .fortress, .park, .nationalPark, .beach, .marina,
             .campground, .rvPark:
            return "news"
        default:
            // Mundane POIs (atm, gasStation, parking, pharmacy, hospital, bank, police,
            // fireStation, postOffice, restroom, laundry, carRental, evCharger, …) pop nothing.
            return nil
        }
    }

    // MARK: - Name keyword → channel (overrides category)

    private static func channel(forName name: String) -> String? {
        guard !name.isEmpty else { return nil }
        let sports = ["basketball", "baseball", "soccer", "football", "tennis", "golf",
                      "hockey", "volleyball", "arena", "stadium", "gym", "athletic"]
        let food = ["pizza", "sushi", "burger", "taco", "coffee", "cafe", "donut",
                    "bakery", "grill", "kitchen", "restaurant", "bbq", "ramen", "diner"]
        let fashion = ["boutique", "fashion", "apparel", "clothing", "shoe", "sneaker",
                       "outfitters"]
        let beauty = ["salon", "beauty", "cosmetic", "nail", "makeup", "spa"]
        let music = ["music", "records", "concert", "nightclub", "lounge", "bar ", "club"]
        let tech = ["electronics", "apple store", "computer", "tech", "gaming"]

        func has(_ list: [String]) -> Bool { list.contains { name.contains($0) } }

        if has(sports)  { return "sports" }
        if has(food)    { return "food" }
        if has(beauty)  { return "beauty" }
        if has(fashion) { return "fashion" }
        if has(music)   { return "music" }
        if has(tech)    { return "tech" }
        return nil
    }
}
