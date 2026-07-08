import Foundation

enum PopularObjectCatalog {
    private static let objectsByChannel: [String: [String]] = [
        "beauty": ["beauty_lipstick", "beauty_makeup_brush", "beauty_perfume", "beauty_foundation", "beauty_nail_polish", "beauty_eyeshadow_palette", "beauty_mascara", "beauty_cream_jar", "beauty_lip_gloss", "beauty_beauty_tube", "beauty_beauty_blender", "beauty_compact_powder", "beauty_serum_bottle", "beauty_false_lashes", "beauty_hair_straightener", "beauty_hair_dryer", "beauty_face_mask", "beauty_powder_compact", "beauty_nail_set", "beauty_vanity_mirror"],
        "fashion": ["fashion_handbag", "fashion_hoodie", "fashion_sneaker", "fashion_sunglasses", "fashion_watch", "fashion_t_shirt", "fashion_jeans", "fashion_cap", "fashion_puffer_jacket", "fashion_belt", "fashion_high_heel", "fashion_ring", "fashion_necklace", "fashion_dress", "fashion_shopping_bag", "fashion_perfume", "fashion_hanger", "fashion_wallet", "fashion_beanie", "fashion_black_sunglasses"],
        "fitness": ["fitness_dumbbell", "fitness_kettlebell", "fitness_shaker_bottle", "fitness_running_shoe", "fitness_smart_watch", "fitness_headphones", "fitness_yoga_mat", "fitness_spin_bike", "fitness_boxing_glove", "fitness_water_bottle", "fitness_weight_plate", "fitness_fitness_band", "fitness_gym_bag", "fitness_foam_roller", "fitness_parallel_bars", "fitness_barbell", "fitness_medicine_ball", "fitness_jump_rope", "fitness_flexed_arm", "fitness_heart_pulse"],
        "food": ["food_burger", "food_pizza_slice", "food_sushi", "food_french_fries", "food_taco", "food_donut", "food_cupcake", "food_chicken_drumstick", "food_ice_cream_cone", "food_hot_dog", "food_sandwich", "food_boba_tea", "food_salad_bowl", "food_popcorn", "food_avocado", "food_waffle", "food_cheese_wedge", "food_coffee_cup", "food_cookie", "food_banana"],
        "french": ["french_eiffel_tower", "french_french_flag", "french_croissant", "french_beret", "french_espresso", "french_cheese", "french_wine", "french_macarons", "french_bicycle", "french_baguette", "french_perfume_bottle", "french_arc_de_triomphe", "french_mime_mask", "french_lavender", "french_poodle", "french_cathedral", "french_dress_form", "french_escargot", "french_france_map", "french_street_lamp"],
        "modelling": ["modelling_camera", "modelling_studio_light", "modelling_director_chair", "modelling_mannequin_torso", "modelling_pose_model", "modelling_comp_cards", "modelling_vanity_mirror", "modelling_runway", "modelling_high_heel", "modelling_portfolio_book", "modelling_agency_badge", "modelling_measuring_tape", "modelling_headshots", "modelling_necklace_display", "modelling_clipboard", "modelling_sunglasses", "modelling_model_pose", "modelling_makeup_chair", "modelling_backdrop", "modelling_crown"],
        "music": ["music_headphones", "music_microphone", "music_speaker", "music_electric_guitar", "music_music_note", "music_keyboard", "music_vinyl_record", "music_boombox", "music_drum", "music_xylophone", "music_treble_clef", "music_mixer", "music_cassette", "music_acoustic_guitar", "music_equalizer", "music_maracas", "music_turntable", "music_music_app_icon", "music_studio_monitor", "music_gold_record"],
        "news": ["news_newspaper", "news_news_microphone", "news_video_camera", "news_globe", "news_satellite_dish", "news_press_id", "news_notepad", "news_megaphone", "news_news_van", "news_live_tv", "news_news_laptop", "news_chat_bubbles", "news_hourglass", "news_chart", "news_fact_check", "news_camera_lens", "news_typewriter", "news_reporter_microphone", "news_podium", "news_news_clipboard"],
        "spanish": ["spanish_spain_flag", "spanish_flamenco_dancer", "spanish_spanish_guitar", "spanish_paella", "spanish_soccer_ball", "spanish_hand_fan", "spanish_bull", "spanish_sangria", "spanish_sombrero", "spanish_tapas", "spanish_sagrada_familia", "spanish_beach_umbrella", "spanish_olives", "spanish_castanets", "spanish_olive_oil", "spanish_chili_pepper", "spanish_surfboard", "spanish_windmill", "spanish_orange_tree", "spanish_sailboat"],
        "sports": ["sports_soccer_ball", "sports_basketball", "sports_football", "sports_tennis_ball", "sports_baseball", "sports_volleyball", "sports_golf_ball", "sports_boxing_glove", "sports_helmet", "sports_shuttlecock", "sports_hockey_puck", "sports_tennis_racket", "sports_baseball_bat", "sports_bike_helmet", "sports_trophy", "sports_stopwatch", "sports_cleats", "sports_golf_club", "sports_surfboard", "sports_basketball_hoop"],
        "tech": ["tech_smartphone", "tech_laptop", "tech_game_controller", "tech_earbuds", "tech_smart_watch", "tech_vr_headset", "tech_drone", "tech_tablet", "tech_camera", "tech_smart_speaker", "tech_mouse", "tech_keyboard", "tech_monitor", "tech_graphics_card", "tech_robot_head", "tech_power_bank", "tech_hard_drive", "tech_router", "tech_microchip", "tech_light_bulb"],
    ]
    private static let channelAliases: [String: String] = [
        "beauty": "beauty",
        "fashion": "fashion",
        "fitness": "fitness",
        "food": "food",
        "french": "french",
        "gaming": "tech",
        "modelling": "modelling",
        "music": "music",
        "news": "news",
        "shopping": "fashion",
        "spanish": "spanish",
        "sports": "sports",
        "style": "beauty",
        "tech": "tech",
        "ad": "news",
        "ads": "news",
        "creative": "modelling",
        "3d": "tech"
    ]
    private static let legacyObjectIds: [String: String] = [
        "bag": "fashion_handbag",
        "ball": "sports_soccer_ball",
        "banana": "food_banana",
        "beret": "french_beret",
        "cake": "food_cupcake",
        "camera": "modelling_camera",
        "chip": "tech_microchip",
        "compact": "beauty_compact_powder",
        "controller": "tech_game_controller",
        "croissant": "french_croissant",
        "dress": "fashion_dress",
        "dumbbell": "fitness_dumbbell",
        "eiffel": "french_eiffel_tower",
        "fan": "spanish_hand_fan",
        "fruit": "food_avocado",
        "globe": "news_globe",
        "guitar": "spanish_spanish_guitar",
        "laptop": "tech_laptop",
        "lipstick": "beauty_lipstick",
        "microphone": "music_microphone",
        "newspaper": "news_newspaper",
        "note": "music_music_note",
        "phone": "tech_smartphone",
        "shoe": "fashion_sneaker",
        "sparkle": "beauty_eyeshadow_palette",
        "speaker": "music_speaker",
        "spotlight": "modelling_studio_light",
        "star": "news_fact_check",
        "sun": "spanish_beach_umbrella",
        "trophy": "sports_trophy",
    ]
    static let assetIds: Set<String> = Set(objectsByChannel.values.flatMap { $0 })

    /// A single representative object for a channel — used when a location matches a
    /// category (e.g. a stadium) but no more specific object name could be resolved.
    static func representative(for channelId: String) -> String {
        let reps: [String: String] = [
            "sports": "sports_basketball",
            "food": "food_burger",
            "fashion": "fashion_handbag",
            "beauty": "beauty_lipstick",
            "fitness": "fitness_dumbbell",
            "music": "music_microphone",
            "news": "news_newspaper",
            "tech": "tech_laptop",
            "modelling": "modelling_camera",
            "french": "french_eiffel_tower",
            "spanish": "spanish_spanish_guitar",
        ]
        return reps[channelId] ?? objectsByChannel[channelId]?.first ?? "news_newspaper"
    }

    /// Find the most specific object whose asset id matches a keyword found in `nameHint`
    /// (e.g. a POI named "…Basketball Arena" → `sports_basketball`). Prefers objects in
    /// `channelId`, then falls back to any channel.
    static func specificObject(nameHint: String, channelId: String) -> String? {
        let words = Set(
            nameHint.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }
        )
        guard !words.isEmpty else { return nil }

        func match(in ids: [String]) -> String? {
            for id in ids {
                // suffix after "channel_"
                let suffix = id.drop { $0 != "_" }.dropFirst().replacingOccurrences(of: "_", with: " ")
                for word in words where suffix.contains(word) {
                    return id
                }
            }
            return nil
        }

        if let inChannel = objectsByChannel[channelId], let hit = match(in: inChannel) {
            return hit
        }
        return match(in: objectsByChannel.values.flatMap { $0 })
    }

    static func randomObject(for channelId: String) -> String {
        objects(for: channelId).randomElement() ?? "news_newspaper"
    }

    static func object(for channelId: String, seed: Int) -> String {
        let options = objects(for: channelId)
        guard !options.isEmpty else { return "news_newspaper" }
        return options[abs(seed) % options.count]
    }

    static func objects(for channelId: String) -> [String] {
        let normalized = channelId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let canonical = channelAliases[normalized] ?? channelAliases.first(where: { normalized.contains($0.key) })?.value ?? "news"
        return objectsByChannel[canonical] ?? objectsByChannel["news"] ?? []
    }

    static func assetURL(for objectId: String, channelId: String? = nil) -> URL? {
        let normalized = objectId.replacingOccurrences(of: "popular:", with: "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let assetId: String
        if assetIds.contains(normalized) {
            assetId = normalized
        } else if let legacy = legacyObjectIds[normalized] {
            assetId = legacy
        } else if let channelId, let first = objectsByChannel[channelId.lowercased()]?.first(where: { $0.hasSuffix("_\(normalized)") }) {
            assetId = first
        } else {
            return nil
        }
        let channel = String(assetId.split(separator: "_").first ?? "news")
        return Bundle.main.url(forResource: assetId, withExtension: "dae", subdirectory: "PopularObjects/\(channel)")
    }

    static func object(forDetectedLabel label: String) -> String? {
        let normalized = label.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        if normalized.contains("burger") || normalized.contains("sandwich") || normalized.contains("pizza") || normalized.contains("sushi") || normalized.contains("fries") || normalized.contains("taco") || normalized.contains("donut") || normalized.contains("cupcake") || normalized.contains("food") || normalized.contains("meal") || normalized.contains("plate") || normalized.contains("banana") || normalized.contains("coffee") || normalized.contains("cookie") || normalized.contains("popcorn") || normalized.contains("salad") || normalized.contains("avocado") { return "food_burger" }
        if normalized.contains("lipstick") || normalized.contains("makeup") || normalized.contains("beauty") || normalized.contains("cosmetic") || normalized.contains("mascara") || normalized.contains("nail") || normalized.contains("perfume") || normalized.contains("mirror") || normalized.contains("hair dryer") { return "beauty_lipstick" }
        if normalized.contains("dumbbell") || normalized.contains("barbell") || normalized.contains("weight") || normalized.contains("exercise") || normalized.contains("fitness") || normalized.contains("gym") || normalized.contains("yoga") || normalized.contains("bike") || normalized.contains("water bottle") { return "fitness_dumbbell" }
        if normalized.contains("ball") || normalized.contains("soccer") || normalized.contains("basketball") || normalized.contains("football") || normalized.contains("tennis") || normalized.contains("baseball") || normalized.contains("sports") || normalized.contains("helmet") || normalized.contains("trophy") || normalized.contains("golf") { return "sports_soccer_ball" }
        if normalized.contains("camera") || normalized.contains("lens") || normalized.contains("photography") || normalized.contains("person") || normalized.contains("human") || normalized.contains("face") || normalized.contains("portrait") || normalized.contains("selfie") || normalized.contains("model") || normalized.contains("runway") || normalized.contains("studio") { return "modelling_camera" }
        if normalized.contains("dress") || normalized.contains("clothing") || normalized.contains("shirt") || normalized.contains("jacket") || normalized.contains("fashion") || normalized.contains("shoe") || normalized.contains("sneaker") || normalized.contains("bag") || normalized.contains("purse") || normalized.contains("handbag") || normalized.contains("watch") || normalized.contains("sunglasses") { return "fashion_dress" }
        if normalized.contains("microphone") || normalized.contains("mic") || normalized.contains("music") || normalized.contains("instrument") || normalized.contains("song") || normalized.contains("speaker") || normalized.contains("headphones") || normalized.contains("guitar") || normalized.contains("keyboard") || normalized.contains("drum") { return "music_microphone" }
        if normalized.contains("laptop") || normalized.contains("computer") || normalized.contains("keyboard") || normalized.contains("monitor") || normalized.contains("screen") || normalized.contains("consumer electronics") || normalized.contains("electronic") || normalized.contains("machine") || normalized.contains("television") || normalized.contains("tv") || normalized.contains("tablet") || normalized.contains("phone") || normalized.contains("mobile") || normalized.contains("smartphone") || normalized.contains("controller") || normalized.contains("game") || normalized.contains("robot") || normalized.contains("drone") { return "tech_laptop" }
        if normalized.contains("newspaper") || normalized.contains("paper") || normalized.contains("document") || normalized.contains("book") || normalized.contains("magazine") || normalized.contains("news") || normalized.contains("globe") || normalized.contains("world") || normalized.contains("earth") || normalized.contains("map") || normalized.contains("notepad") || normalized.contains("megaphone") { return "news_newspaper" }
        if normalized.contains("eiffel") || normalized.contains("croissant") || normalized.contains("beret") || normalized.contains("french") || normalized.contains("baguette") || normalized.contains("wine") || normalized.contains("cheese") { return "french_eiffel_tower" }
        if normalized.contains("guitar") || normalized.contains("spanish") || normalized.contains("spain") || normalized.contains("fan") || normalized.contains("paella") || normalized.contains("sombrero") || normalized.contains("flamenco") { return "spanish_spanish_guitar" }
        return nil
    }
}
