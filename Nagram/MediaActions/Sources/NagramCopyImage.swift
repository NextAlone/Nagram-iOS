import AccountContext
import Display
import Foundation
import ImageIO
import NagramStrings
import OverlayStatusController
import SaveToCameraRoll
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UIKit
import UndoUI

public func nagramCopyImage(context: AccountContext, media: AnyMediaReference, userLocation: MediaResourceUserLocation, presentationData: PresentationData, present: @escaping (ViewController) -> Void) -> Disposable {
    let operation = MetaDisposable()
    weak var loadingReference: ViewController?
    let loading = OverlayStatusController(style: presentationData.theme.overallDarkAppearance ? .dark : .light, type: .loading(cancelled: {
        operation.dispose()
        loadingReference?.dismiss()
    }))
    loadingReference = loading
    present(loading)
    let showError = {
        loading.dismiss()
        let alert = ActionSheetController(presentationData: presentationData)
        alert.setItemGroups([ActionSheetItemGroup(items: [
            ActionSheetTextItem(title: ngI18n("Nagram.CopyImageFailed", presentationData.strings.baseLanguageCode)),
            ActionSheetButtonItem(title: presentationData.strings.Common_OK, color: .accent, action: { [weak alert] in
                alert?.dismissAnimated()
            })
        ])])
        present(alert)
    }
    var receivedData = false
    operation.set((fetchMediaData(context: context, userLocation: userLocation, mediaReference: media)
    |> filter { value, _ in
        if case let .data(data) = value {
            return data.isComplete
        }
        return false
    }
    |> take(1)
    |> deliverOnMainQueue).start(next: { value, isImage in
        receivedData = true
        guard isImage, case let .data(resource) = value,
              let data = try? Data(contentsOf: URL(fileURLWithPath: resource.path), options: .mappedIfSafe),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0, let type = CGImageSourceGetType(source) else {
            showError()
            return
        }
        UIPasteboard.general.setData(data, forPasteboardType: type as String)
        loading.dismiss()
        present(UndoOverlayController(presentationData: presentationData, content: .copy(text: ngI18n("Nagram.ImageCopied", presentationData.strings.baseLanguageCode)), elevatedLayout: false, animateInAsReplacement: false, action: { _ in false }))
    }, completed: {
        if !receivedData {
            showError()
        }
    }))
    return ActionDisposable {
        operation.dispose()
        Queue.mainQueue().async {
            loading.dismiss()
        }
    }
}
