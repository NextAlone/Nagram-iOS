import Foundation
import NagramSettings
import UIKit

// MARK: NAGRAM — tg:// / telegram:// 链接转交给官方 Telegram。
// iOS 的 URL scheme 写在 Info.plist 里，运行时无法取消注册，所以「注册 Telegram 链接」关闭后，
// 系统仍然会先打开 Nagram，这里再把链接交给官方 Telegram 处理。
// 转交失败（未安装官方 Telegram，或系统拒绝）时回落到 Nagram 自己处理，链接不会失效。

/// 官方 Telegram iOS 的专属 scheme（见 Telegram/Telegram-iOS/Config-AppStoreLLC.xcconfig）。
/// 用它而不是 tg://，才能避免链接被 Nagram 自己重新接住。
private let nagramOfficialTelegramScheme = "tgapp"

/// 需要转交的 scheme。na:// 和 nagram:// 是 Nagram 自己的入口，永不转交。
private let nagramForwardedTelegramSchemes: Set<String> = ["tg", "telegram"]

/// Nagram 自己生成的内部深链（小组件、导入完成后的跳转），不参与转交。
private let nagramInternalTelegramHosts: Set<String> = ["localpeer"]

/// 把外部 tg:// / telegram:// 链接改写成官方 Telegram 能接住的 tgapp:// 链接。
/// 返回 nil 表示这个链接应该留给 Nagram 处理。
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
    return URL(string: nagramOfficialTelegramScheme + String(value[separator...]))
}

/// 尝试把链接交给官方 Telegram。返回 true 表示系统已经接管，调用方不用再走内部逻辑；
/// 接管失败时执行 fallback，让链接退回 Nagram 自己处理。
func nagramForwardTelegramSchemeUrl(_ url: URL, fallback: @escaping () -> Void) -> Bool {
    guard let forwarded = nagramOfficialTelegramUrl(url) else {
        return false
    }
    DispatchQueue.main.async {
        UIApplication.shared.open(forwarded, options: [:], completionHandler: { success in
            if !success {
                fallback()
            }
        })
    }
    return true
}
