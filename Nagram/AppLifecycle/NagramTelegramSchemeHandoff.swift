import Foundation
import NagramSettings
import UIKit

// MARK: NAGRAM — tg:// / telegram:// 链接转交给官方 Telegram。
// iOS 的 URL scheme 写在 Info.plist 里，运行时无法取消注册，所以「注册 Telegram 链接」关闭后，
// 系统仍然会先打开 Nagram，这里再把链接交给官方 Telegram 处理。
// 官方 App 注册的 scheme 与 Nagram 相同，无法用 scheme 只指向官方，所以改走 t.me
// Universal Link：t.me 的 apple-app-site-association 只列了官方 App 的 ID，
// `.universalLinksOnly` 打开时只会由官方 App 接住；未安装官方 App 时系统返回 false，
// 正好回落到 Nagram 自己处理，链接不会失效。
// 参数映射与 App 自己打开 tg:// 链接时的转换保持一致（TelegramUI OpenUrl.swift 的
// resolve 分支）；映射不了或校验不过的链接留在 Nagram，不转交。

/// 需要转交的 scheme。na:// 和 nagram:// 是 Nagram 自己的入口，永不转交。
private let nagramForwardedTelegramSchemes: Set<String> = ["tg", "telegram"]

/// Nagram 自己生成的内部深链（小组件、导入完成后的跳转），不参与转交。
private let nagramInternalTelegramHosts: Set<String> = ["localpeer"]

/// 用户名 / bot name：拼进 t.me 路径前允许的字符。
private let nagramTelegramMeUsernameSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")

/// 邀请码 / 贴纸包 / 文件夹 / 语言包 code：base64url，语言包额外允许连字符。
private let nagramTelegramMeSlugSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")

/// tg://resolve 里 App 自己认得的全部参数（OpenUrl.swift resolve 分支）。
/// 之外的参数没有 t.me 形式，转交必丢，整条链接留给 Nagram。
private let nagramResolveParameterNames: Set<String> = [
    "phone", "domain", "start", "startgroup", "startchannel", "admin", "game", "post",
    "voicechat", "videochat", "livestream", "attach", "startattach", "choose", "thread",
    "appname", "startapp", "text", "ref", "album", "collection", "profile", "direct"
]

private func nagramIsValidPathSegment(_ value: String, allowed: CharacterSet) -> Bool {
    return !value.isEmpty && value.rangeOfCharacter(from: allowed.inverted) == nil
}

private func nagramIsValidPhoneNumber(_ value: String) -> Bool {
    return !value.isEmpty && value.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789").inverted) == nil
}

/// tg://resolve → t.me，逐项对应 TelegramUI OpenUrl.swift 里 App 自己的转换。
/// 返回 nil 表示这条链接没有完整的 t.me 形式，留给 Nagram 处理。
private func nagramResolveToTelegramMe(_ items: [URLQueryItem]) -> URLComponents? {
    func first(_ name: String) -> String? {
        return items.first(where: { $0.name == name })?.value
    }
    func present(_ name: String) -> Bool {
        return items.contains(where: { $0.name == name })
    }
    func valueless(_ name: String) -> Bool {
        return items.contains(where: { $0.name == name && $0.value == nil })
    }

    // 参数超出 App 自己认得的集合（含 passport / oauth 专用的 bot_id、scope、payload、
    // nonce、public_key、callback_url）时，转交必然丢参数，不转交。
    if !Set(items.map { $0.name }).isSubset(of: nagramResolveParameterNames) {
        return nil
    }

    var path: String
    if let phone = first("phone") {
        guard nagramIsValidPhoneNumber(phone) else {
            return nil
        }
        path = "/+\(phone)"
    } else if let domain = first("domain"), domain != "telegrampassport", nagramIsValidPathSegment(domain, allowed: nagramTelegramMeUsernameSet) {
        path = "/\(domain)"
        if let appName = first("appname"), nagramIsValidPathSegment(appName, allowed: nagramTelegramMeUsernameSet) {
            path += "/\(appName)"
        }
        if let threadValue = first("thread"), let threadId = Int64(threadValue) {
            path += "/\(threadId)"
            if let post = first("post"), let postValue = Int(post) {
                path += "/\(postValue)"
            }
        } else if let post = first("post"), let postValue = Int(post) {
            path += "/\(postValue)"
        }
        if let album = first("album"), let albumId = Int64(album) {
            path += "/a/\(albumId)"
        } else if let collection = first("collection"), let collectionId = Int64(collection) {
            path += "/c/\(collectionId)"
        }
    } else {
        return nil
    }

    var queryItems: [URLQueryItem] = []
    if let startApp = first("startapp") {
        queryItems.append(URLQueryItem(name: "startapp", value: startApp.isEmpty ? "" : startApp))
    }
    if let start = first("start") {
        queryItems.append(URLQueryItem(name: "start", value: start))
    } else if present("startgroup") {
        let value = first("startgroup")
        queryItems.append(URLQueryItem(name: "startgroup", value: (value ?? "").isEmpty ? nil : value))
        if let admin = first("admin") {
            queryItems.append(URLQueryItem(name: "admin", value: admin))
        }
    } else if present("startchannel") {
        let value = first("startchannel")
        queryItems.append(URLQueryItem(name: "startchannel", value: (value ?? "").isEmpty ? nil : value))
        if let admin = first("admin") {
            queryItems.append(URLQueryItem(name: "admin", value: admin))
        }
    } else if let game = first("game") {
        queryItems.append(URLQueryItem(name: "game", value: game))
    } else if ["voicechat", "videochat", "livestream"].contains(where: { present($0) }) {
        var voiceChat: String?
        for item in items where ["voicechat", "videochat", "livestream"].contains(item.name) {
            voiceChat = item.value ?? ""
        }
        queryItems.append(URLQueryItem(name: "voicechat", value: voiceChat ?? ""))
    } else if let attach = first("attach") {
        queryItems.append(URLQueryItem(name: "attach", value: attach))
    }
    if present("startattach") {
        let value = first("startattach")
        queryItems.append(URLQueryItem(name: "startattach", value: (value ?? "").isEmpty ? nil : value))
        if let choose = first("choose") {
            queryItems.append(URLQueryItem(name: "choose", value: choose))
        }
    }
    if let text = first("text") {
        queryItems.append(URLQueryItem(name: "text", value: text))
    }
    if let referrer = first("ref") {
        queryItems.append(URLQueryItem(name: "ref", value: referrer))
    }
    if valueless("profile") {
        queryItems.append(URLQueryItem(name: "profile", value: nil))
    }
    if valueless("direct") {
        queryItems.append(URLQueryItem(name: "direct", value: nil))
    }

    var components = URLComponents()
    components.scheme = "https"
    components.host = "t.me"
    components.path = path
    if !queryItems.isEmpty {
        components.queryItems = queryItems
    }
    return components
}

/// 把 tg:// / telegram:// 链接改写成只有官方 Telegram 能接住的 t.me Universal Link。
/// 返回 nil 表示这个链接没有 t.me 对应形式，留给 Nagram 处理。
func nagramOfficialTelegramUrl(_ url: URL) -> URL? {
    if NagramSettings.shared.registerTelegramLinks {
        return nil
    }
    let value = url.absoluteString
    guard let separator = value.firstIndex(of: ":"), nagramForwardedTelegramSchemes.contains(String(value[..<separator]).lowercased()) else {
        return nil
    }
    // 没有 host 的 tg:// 只是「打开应用」，官方 Telegram 无从判断意图，留给 Nagram。
    let host = url.host?.lowercased() ?? ""
    guard !host.isEmpty, !nagramInternalTelegramHosts.contains(host) else {
        return nil
    }
    guard let components = URLComponents(string: value) else {
        return nil
    }
    let items = components.queryItems ?? []

    var tmeComponents: URLComponents?
    switch host {
    case "resolve":
        // tg://resolve?domain=x&start=… → https://t.me/x?start=…（全参数映射）
        tmeComponents = nagramResolveToTelegramMe(items)
    case "join":
        // tg://join?invite=x → https://t.me/+x；只认唯一参数，带其他参数的留给 Nagram。
        if items.count == 1, items[0].name == "invite", let invite = items[0].value, nagramIsValidPathSegment(invite, allowed: nagramTelegramMeSlugSet) {
            tmeComponents = URLComponents(string: "https://t.me/+" + invite)
        }
    case "addstickers":
        // tg://addstickers?set=x → https://t.me/addstickers/x
        if items.count == 1, items[0].name == "set", let set = items[0].value, nagramIsValidPathSegment(set, allowed: nagramTelegramMeSlugSet) {
            tmeComponents = URLComponents(string: "https://t.me/addstickers/" + set)
        }
    case "addlist":
        // tg://addlist?slug=x → https://t.me/addlist/x
        if items.count == 1, items[0].name == "slug", let slug = items[0].value, nagramIsValidPathSegment(slug, allowed: nagramTelegramMeSlugSet) {
            tmeComponents = URLComponents(string: "https://t.me/addlist/" + slug)
        }
    case "setlanguage":
        // tg://setlanguage?lang=x → https://t.me/setlanguage/x
        if items.count == 1, items[0].name == "lang", let lang = items[0].value, nagramIsValidPathSegment(lang, allowed: nagramTelegramMeSlugSet) {
            tmeComponents = URLComponents(string: "https://t.me/setlanguage/" + lang)
        }
    case "msg_url":
        // tg://msg_url?url=x&text=y → https://t.me/share/url?url=x&text=y（保留全部参数）
        if !items.isEmpty {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "t.me"
            components.path = "/share/url"
            components.queryItems = items
            tmeComponents = components
        }
    default:
        break
    }
    return tmeComponents?.url
}

/// 尝试把链接交给官方 Telegram。返回 true 表示系统已经接管，调用方不用再走内部逻辑；
/// 接管失败（未安装官方 Telegram）时执行 fallback，让链接退回 Nagram 自己处理。
func nagramForwardTelegramSchemeUrl(_ url: URL, fallback: @escaping () -> Void) -> Bool {
    guard let forwarded = nagramOfficialTelegramUrl(url) else {
        return false
    }
    DispatchQueue.main.async {
        UIApplication.shared.open(forwarded, options: [.universalLinksOnly: true], completionHandler: { success in
            if !success {
                fallback()
            }
        })
    }
    return true
}
