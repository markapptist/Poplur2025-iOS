import Foundation

enum AITranslationCaptionProvider {
    static func sourceLanguage(for channelID: String) -> PoplurLanguage {
        switch channelID {
        case "french":
            return .french
        case "spanish":
            return .spanish
        default:
            return .english
        }
    }

    static func sourceLanguage(for post: FeedPost) -> PoplurLanguage {
        PoplurLanguage.fromCode(post.sourceLanguageCode)
    }

    static func caption(
        for post: FeedPost,
        channelCategory: String,
        preferredLanguage: PoplurLanguage,
        playbackSeconds: Double = 0
    ) -> String {
        let sourceLanguage = sourceLanguage(for: post)
        let city = post.cityName ?? "the city"
        let category = channelCategory.lowercased()

        if isDemoDramaPost(post) {
            return dramaCaption(
                sourceLanguage: sourceLanguage,
                preferredLanguage: preferredLanguage,
                playbackSeconds: playbackSeconds
            )
        }

        let translated = translatedCaption(
            sourceLanguage: sourceLanguage,
            preferredLanguage: preferredLanguage,
            city: city,
            category: category
        )

        if sourceLanguage == preferredLanguage {
            return translated
        }

        return translated
    }

    static func translationBadge(
        for post: FeedPost,
        preferredLanguage: PoplurLanguage
    ) -> String {
        let sourceLanguage = sourceLanguage(for: post)
        if sourceLanguage == preferredLanguage {
            return "CC \(preferredLanguage.shortName)"
        }
        return "AI \(sourceLanguage.shortName) -> \(preferredLanguage.shortName)"
    }

    private static func translatedCaption(
        sourceLanguage: PoplurLanguage,
        preferredLanguage: PoplurLanguage,
        city: String,
        category: String
    ) -> String {
        switch preferredLanguage {
        case .english:
            switch sourceLanguage {
            case .english:
                return "Live from \(city). New \(category) clips are coming in now."
            case .french:
                return "Translated from French: Live from \(city), with new \(category) clips coming in now."
            case .spanish:
                return "Translated from Spanish: Live from \(city), with new \(category) clips coming in now."
            }
        case .french:
            switch sourceLanguage {
            case .english:
                return "Traduit de l'anglais : en direct de \(city), avec de nouvelles videos \(category)."
            case .french:
                return "En direct de \(city). De nouvelles videos \(category) arrivent maintenant."
            case .spanish:
                return "Traduit de l'espagnol : en direct de \(city), avec de nouvelles videos \(category)."
            }
        case .spanish:
            switch sourceLanguage {
            case .english:
                return "Traducido del ingles: en vivo desde \(city), con nuevos videos de \(category)."
            case .french:
                return "Traducido del frances: en vivo desde \(city), con nuevos videos de \(category)."
            case .spanish:
                return "En vivo desde \(city). Estan llegando nuevos videos de \(category)."
            }
        }
    }

    private static func isDemoDramaPost(_ post: FeedPost) -> Bool {
        let lowerID = post.id.lowercased()
        let lowerURL = post.mediaURL.lowercased()
        return lowerID.contains("demo")
            || lowerURL.contains("guiding_light")
            || lowerURL.contains("guidinglight")
            || lowerURL.contains("love_of_life")
            || lowerURL.contains("loveoflife")
            || lowerURL.contains("valiant_lady")
            || lowerURL.contains("1967_pd_soapie")
    }

    private static func dramaCaption(
        sourceLanguage: PoplurLanguage,
        preferredLanguage: PoplurLanguage,
        playbackSeconds: Double
    ) -> String {
        let elapsed = max(0, playbackSeconds)
        let cueIndex = dramaCueStartTimes.lastIndex { elapsed >= $0 } ?? 0
        let line: String

        switch preferredLanguage {
        case .english:
            line = englishDramaLines[cueIndex]
        case .french:
            line = frenchDramaLines[cueIndex]
        case .spanish:
            line = spanishDramaLines[cueIndex]
        }

        guard sourceLanguage != preferredLanguage else { return line }

        switch preferredLanguage {
        case .english:
            return "Translated from \(sourceLanguage.shortName): \(line)"
        case .french:
            return "Traduit depuis \(sourceLanguage.shortName) : \(line)"
        case .spanish:
            return "Traducido de \(sourceLanguage.shortName): \(line)"
        }
    }

    private static let englishDramaLines: [String] = [
        "[door opens] Margaret, tell me the truth before the whole town hears it.",
        "I tried to protect this family, but the secret was already in the room.",
        "No, Daniel. If you leave now, you may never know who signed that letter.",
        "[telephone rings] Stay quiet. That call is for me.",
        "After everything we built, you still chose the lie.",
        "Previously on Poplur Drama: one promise changed every life in town."
    ]

    private static let frenchDramaLines: [String] = [
        "[porte qui s'ouvre] Margaret, dis-moi la verite avant que toute la ville l'apprenne.",
        "J'ai essaye de proteger cette famille, mais le secret etait deja dans la piece.",
        "Non, Daniel. Si tu pars maintenant, tu ne sauras peut-etre jamais qui a signe cette lettre.",
        "[telephone qui sonne] Reste silencieux. Cet appel est pour moi.",
        "Apres tout ce que nous avons construit, tu as quand meme choisi le mensonge.",
        "Precedemment dans Poplur Drama : une promesse a change toutes les vies en ville."
    ]

    private static let spanishDramaLines: [String] = [
        "[se abre la puerta] Margaret, dime la verdad antes de que todo el pueblo se entere.",
        "Intente proteger a esta familia, pero el secreto ya estaba en la habitacion.",
        "No, Daniel. Si te vas ahora, tal vez nunca sepas quien firmo esa carta.",
        "[suena el telefono] Guarda silencio. Esa llamada es para mi.",
        "Despues de todo lo que construimos, aun elegiste la mentira.",
        "Anteriormente en Poplur Drama: una promesa cambio cada vida del pueblo."
    ]

    private static let dramaCueStartTimes: [Double] = [0, 5.2, 10.8, 16.4, 22.0, 28.5]
}
