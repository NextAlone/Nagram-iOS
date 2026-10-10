import Foundation
import NagramSettings
import UIKit

// MARK: NAGRAM — tg:// / telegram:// 链接转交给官方 Telegram。
// iOS 的 URL scheme 写在 Info.plist 里，运行时无法取消注册，所以「注册 Telegram 链接」关闭后，
// 系统仍然会先打开 Nagram，这里再把链接交给官方 Telegram 处理。
// 官方 App 注册的 scheme 与 Nagram 相同，无法用 scheme 只指向官方，所以改走 t.me
// Universal Link：t.me 的 apple-app-site-association 只列了官方 App 的 ID，
// `.universalLinksOnly` 打开时只会由官方 App 接住；未安装官方 App 时系统返回 false，
// 正好回落到 Nagram 自己处理，链接不会失效。没有 t.me 对应形式的链接（tg://settings、
// tg://user?id= 等）继续留给 Nagram。

/// 需要转交的 scheme。na:// 和 nagram:// 是 Nagram 自己的入口，永不转交。
private let nagramForwardedTelegramSchemes: Set<String> = ["tg", "telegram"]

/// Nagram 自己生成的内部深链（小组件、导入完成后的跳转），不参与转交。
private let nagramInternalTelegramHosts: Set<String> = ["localpeer"]

private func nagramFirstQueryItem(_ value: String, name: String) -> String? {
    guard let items = URLComponents(string: value)?.queryItems else {
        return nil
    }
    return items.first(where: { $0.name == name })?.value
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

    var tmeComponents: URLComponents?
    switch host {
    case "resolve":
        // tg://resolve?domain=x → https://t.me/x
        if let domain = nagramFirstQueryItem(value, name: "domain"), !domain.isEmpty {
            tmeComponents = URLComponents(string: "https://t.me/" + domain)
        }
    case "join":
        // tg://join?invite=x → https://t.me/+x
        if let invite = nagramFirstQueryItem(value, name: "invite"), !invite.isEmpty {
            tmeComponents = URLComponents(string: "https://t.me/+" + invite)
        }
    case "addstickers":
        // tg://addstickers?set=x → https://t.me/addstickers/x
        if let set = nagramFirstQueryItem(value, name: "set"), !set.isEmpty {
            tmeComponents = URLComponents(string: "https://t.me/addstickers/" + set)
        }
    case "addlist":
        // tg://addlist?slug=x → https://t.me/addlist/x
        if let slug = nagramFirstQueryItem(value, name: "slug"), !slug.isEmpty {
            tmeComponents = URLComponents(string: "https://t.me/addlist/" + slug)
        }
    case "setlanguage":
        // tg://setlanguage?lang=x → https://t.me/setlanguage/x
        if let lang = nagramFirstQueryItem(value, name: "lang"), !lang.isEmpty {
            tmeComponents = URLComponents(string: "https://t.me/setlanguage/" + lang)
        }
    case "msg_url":
        // tg://msg_url?url=x&text=y → https://t.me/share/url?url=x&text=y（保留全部参数）
        if let items = URLComponents(string: value)?.queryItems, !items.isEmpty {
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
