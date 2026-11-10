import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import AccountContext
import UndoUI
import TranslateUI
import ChatMessageItem
import ChatMessageItemView
import NagramSettings
import NagramStrings

// MARK: NAGRAM — the translate button beside messages ("Translate Button Beside Messages"). Pressing it shows the
// message's translation in its bubble, as a translated chat does, and pressing it again shows the original. Only this
// chat shows it, and only until the chat is closed; nothing is sent or edited.

extension ChatControllerImpl {
    func nagramSetupMessageTranslationButton() {
        guard NagramSettings.shared.messageTranslateButton, let controllerInteraction = self.controllerInteraction else {
            return
        }
        controllerInteraction.nagramToggleMessageTranslation = { [weak self] messageId in
            self?.nagramToggleMessageTranslation(messageId: messageId)
        }

        var baseLanguage = self.presentationData.strings.baseLanguageCode
        let rawSuffix = "-raw"
        if baseLanguage.hasSuffix(rawSuffix) {
            baseLanguage = String(baseLanguage.dropLast(rawSuffix.count))
        }
        let toLanguage = normalizeTranslationLanguage(baseLanguage)

        let context = self.context
        let _ = (context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.translationSettings])
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { [weak self] sharedData in
            guard let self, let controllerInteraction = self.controllerInteraction else {
                return
            }
            let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.translationSettings]?.get(TranslationSettings.self) ?? TranslationSettings.defaultSettings
            // The languages the chat's own translate bar leaves alone ("Do Not Translate"), plus the target itself.
            var ignoredLanguages = Set(effectiveIgnoredTranslationLanguages(context: context, ignoredLanguages: settings.ignoredLanguages).map(normalizeTranslationLanguage))
            ignoredLanguages.insert(toLanguage)
            controllerInteraction.nagramMessageTranslationIgnoredLanguages = ignoredLanguages
            controllerInteraction.nagramMessageTranslationLanguage = toLanguage

            guard self.isNodeLoaded else {
                return
            }
            var messageIds: [EngineMessage.Id] = []
            self.chatDisplayNode.historyNode.forEachVisibleMessageItemNode { itemNode in
                if let item = itemNode.item {
                    messageIds.append(item.message.id)
                }
            }
            for messageId in messageIds {
                controllerInteraction.requestMessageUpdate(messageId, false, nil)
            }
        })
    }

    private func nagramToggleMessageTranslation(messageId: EngineMessage.Id) {
        guard let controllerInteraction = self.controllerInteraction, let toLanguage = controllerInteraction.nagramMessageTranslationLanguage else {
            return
        }
        if controllerInteraction.nagramTranslatedMessageIds.contains(messageId) {
            controllerInteraction.nagramTranslatedMessageIds.remove(messageId)
            controllerInteraction.requestMessageUpdate(messageId, false, nil)
            return
        }
        controllerInteraction.nagramTranslatedMessageIds.insert(messageId)
        controllerInteraction.requestMessageUpdate(messageId, false, nil)

        let context = self.context
        let hasTranslation: () -> Signal<Bool, NoError> = {
            return context.engine.data.get(TelegramEngine.EngineData.Item.Messages.Message(id: messageId))
            |> map { message -> Bool in
                guard let message else {
                    return false
                }
                return message.attributes.contains(where: { attribute in
                    if let attribute = attribute as? TranslationMessageAttribute {
                        return attribute.toLang == toLanguage && !attribute.text.isEmpty
                    }
                    return false
                })
            }
        }
        let _ = (hasTranslation()
        |> mapToSignal { alreadyTranslated -> Signal<Bool, NoError> in
            if alreadyTranslated {
                return .single(true)
            }
            // `translateMessageIds` goes through the configured provider and completes without a translation when
            // it fails, so the result is read back from the message.
            return (translateMessageIds(context: context, messageIds: [messageId], fromLang: nil, toLang: toLanguage)
            |> mapToSignal { _ -> Signal<Bool, NoError> in
                return .complete()
            })
            |> then(hasTranslation())
        }
        |> deliverOnMainQueue).startStandalone(next: { [weak self] translated in
            guard let self, !translated, let controllerInteraction = self.controllerInteraction, controllerInteraction.nagramTranslatedMessageIds.contains(messageId) else {
                return
            }
            controllerInteraction.nagramTranslatedMessageIds.remove(messageId)
            controllerInteraction.requestMessageUpdate(messageId, false, nil)
            let presentationData = self.presentationData
            self.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: ngI18n("Nagram.MessageTranslation.Failed", presentationData.strings.baseLanguageCode), timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
        })
    }
}
