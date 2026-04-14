import Foundation

final class TopCreatorsProvider {
    static let shared = TopCreatorsProvider()
    private init() {}

    // Curated list of top YouTube channel IDs (examples; expand as needed)
    // Source reference: Wikipedia list of most-subscribed YouTube channels
    // Note: These IDs should be maintained/updated periodically.
    let channelIDs: [String] = [
        // T-Series
        "UCq-Fj5jknLsUf-MWSy4_brA",
        // MrBeast
        "UCX6OQ3DkcsbYNE6H8uQQuVA",
        // Cocomelon - Nursery Rhymes
        "UCbCmjCuTUZos6Inko4u57UQ",
        // SET India
        "UCpEhnqL0y41EpW2TvWAHD7Q",
        // Kids Diana Show
        "UCk8GzjMOrta8yxDcKfylJYw",
        // Like Nastya
        "UCJplp5SjeGSdVdwsfb9Q7lQ",
        // PewDiePie
        "UC-lHJZR3Gqxm24_Vd_AJ5Yw",
        // Vlad and Niki
        "UCvlE5gTbOvjiolFlEm-c_Ow",
        // Zee Music Company
        "UCFFbwnve3yF62-tVXkTyHqg",
        // Sony SAB
        "UC6-F5tO8uklgE9Zy8IvbdFw",
        // 5-Minute Crafts
        "UC295-Dw_tDNtZXFeAPAW6Aw",
        // WWE
        "UCJ5v_MCY6GNUBTO8-D3XoAg",
        // BLACKPINK
        "UCOmHUn--16B90oW2L6FRR3A",
        // Justin Bieber
        "UCIwFjwMjI0y7PDBVEO9-bkQ",
        // Marshmello
        "UCeLHszkByNZtPKcaVXOCOQQ",
        // Billie Eilish
        "UCiGm_E4ZwYSHV3bcW1pnSeQ",
        // Ariana Grande
        "UC9CoOnJkIBMdeijd9qYoT_g",
        // Taylor Swift
        "UCANLZYMidaCbLQFWXBC95Jg",
        // Ed Sheeran
        "UC0C-w0YjGpqDXGB8IHb662A",
        // EminemMusic
        "UC2opaZ7rXpqT5iQhQ6G9N0A"
    ]

    func randomChannels(limit: Int) -> [String] {
        if limit >= channelIDs.count { return channelIDs.shuffled() }
        return Array(channelIDs.shuffled().prefix(limit))
    }
}
