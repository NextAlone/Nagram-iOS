import Foundation
import AppBundle

func nagramProfileBadgeString(_ key: String, languageCode: String) -> String {
    let bundle = getAppBundle()
    let normalizedLanguageCode = languageCode.lowercased()
    let languageCode: String
    if normalizedLanguageCode.hasPrefix("zh-hans") || normalizedLanguageCode == "zh-cn" {
        languageCode = "zh-hans"
    } else if normalizedLanguageCode.hasPrefix("zh-hant") || normalizedLanguageCode == "zh-tw" || normalizedLanguageCode == "zh-hk" {
        languageCode = "zh-hant"
    } else if normalizedLanguageCode.hasPrefix("ja") {
        languageCode = "ja"
    } else {
        languageCode = "en"
    }
    if let path = bundle.path(forResource: "NagramLocalizable", ofType: "strings", inDirectory: nil, forLocalization: languageCode), let strings = NSDictionary(contentsOfFile: path) as? [String: String], let value = strings[key] {
        return value
    }
    if let path = bundle.path(forResource: "NagramLocalizable", ofType: "strings", inDirectory: nil, forLocalization: "en"), let strings = NSDictionary(contentsOfFile: path) as? [String: String], let value = strings[key] {
        return value
    }
    return key
}

// MARK: NAGRAM — Profile role badges are maintained by Telegram user ID.
enum NagramProfileBadge: Equatable {
    case developer
    case sponsor
}

private let nagramDeveloperUserIds: Set<Int64> = [
    896711046, // nekohasekai
    380570774, // Haruhi
    784901712, // NextAlone
    457896977, // Queally
    782954985, // MaiTungTM
    1711019015,  // Lagrio
    554072292,  // NahidaBuer
    5412523572, // blxueya
    676660002, // xtao
    1068402676, // Kitsune
    6244360706, // Sevtinge
    625965913,   // YuKongA
    387785790,    // waifucon
    812417693,  // lutit
]

private let nagramSponsorUserIds: Set<Int64> = [
    5382987111,  // Miaoqiqi
    5555116287,  // Natu
]

func nagramProfileBadge(userId: Int64) -> NagramProfileBadge? {
    if nagramDeveloperUserIds.contains(userId) {
        return .developer
    }
    if nagramSponsorUserIds.contains(userId) {
        return .sponsor
    }
    return nil
}

func nagramProfileBadgeTitleKey(_ badge: NagramProfileBadge) -> String {
    switch badge {
    case .developer:
        return "Nagram.ProfileBadge.Developer"
    case .sponsor:
        return "Nagram.ProfileBadge.Sponsor"
    }
}

func nagramProfileBadgeInfoKey(_ badge: NagramProfileBadge) -> String {
    switch badge {
    case .developer:
        return "Nagram.ProfileBadge.Developer.Info"
    case .sponsor:
        return "Nagram.ProfileBadge.Sponsor.Info"
    }
}
