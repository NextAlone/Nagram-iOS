import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import ComponentFlow
import SliderComponent

// MARK: NAGRAM — 行内单值百分比滑杆,完全复刻省电模式 EnergyUsageBatteryLevelItem 的视觉:
// 上排 左「min%」/ 中「当前%」/ 右「max%」,下方 SliderComponent(useNative: true)粗轨道。
// 用于贴纸尺寸(50–200%),参数化 minValue/maxValue。
// 关键:拖动时 valueUpdated 回调里本节点自更新中央「X%」并回写设置;宿主只写值、不重建列表,
// 从而彻底避开「setter → UserDefaults.didChange 同步 → 重入同一属性 getter」的 Swift 独占访问崩溃。
final class NagramSliderItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let minValue: Int32
    let maxValue: Int32
    let value: Int32
    let systemStyle: ItemListSystemStyle
    let sectionId: ItemListSectionId
    let updated: (Int32) -> Void

    init(theme: PresentationTheme, minValue: Int32, maxValue: Int32, value: Int32, sectionId: ItemListSectionId, systemStyle: ItemListSystemStyle = .glass, updated: @escaping (Int32) -> Void) {
        self.theme = theme
        self.minValue = minValue
        self.maxValue = maxValue
        self.value = value
        self.systemStyle = systemStyle
        self.sectionId = sectionId
        self.updated = updated
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = NagramSliderItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? NagramSliderItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async {
                        completion(layout, { _ in apply() })
                    }
                }
            }
        }
    }
}

private final class NagramSliderItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode

    private let slider = ComponentView<Empty>()
    private let leftTextNode: ImmediateTextNode
    private let rightTextNode: ImmediateTextNode
    private let centerTextNode: ImmediateTextNode
    private let centerMeasureTextNode: ImmediateTextNode

    private var item: NagramSliderItem?
    private var layoutParams: ListViewItemLayoutParams?

    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
        self.maskNode = ASImageNode()
        self.leftTextNode = ImmediateTextNode()
        self.rightTextNode = ImmediateTextNode()
        self.centerTextNode = ImmediateTextNode()
        self.centerMeasureTextNode = ImmediateTextNode()

        super.init(layerBacked: false)

        self.addSubnode(self.leftTextNode)
        self.addSubnode(self.rightTextNode)
        self.addSubnode(self.centerTextNode)
    }

    private func sliderPosition(_ value: Int32) -> CGFloat {
        guard let item = self.item else { return 0.0 }
        let span = CGFloat(item.maxValue - item.minValue)
        guard span > 0.0 else { return 0.0 }
        return max(0.0, min(1.0, CGFloat(value - item.minValue) / span))
    }

    func asyncLayout() -> (_ item: NagramSliderItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params, neighbors in
            let separatorHeight = UIScreenPixel
            let separatorRightInset: CGFloat = item.systemStyle == .glass ? 16.0 : 0.0

            var verticalInset: CGFloat = 0.0
            if case .glass = item.systemStyle {
                verticalInset = 4.0
            }

            let contentSize = CGSize(width: params.width, height: 88.0 + verticalInset * 2.0)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size

            return (layout, { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.item = item
                strongSelf.layoutParams = params

                strongSelf.backgroundNode.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                strongSelf.topStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                strongSelf.bottomStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor

                if strongSelf.backgroundNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                }
                if strongSelf.topStripeNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                }
                if strongSelf.bottomStripeNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                }
                if strongSelf.maskNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.maskNode, at: 3)
                }

                let hasCorners = itemListHasRoundedBlockLayout(params)
                var hasTopCorners = false
                var hasBottomCorners = false
                switch neighbors.top {
                case .sameSection(false):
                    strongSelf.topStripeNode.isHidden = true
                default:
                    hasTopCorners = true
                    strongSelf.topStripeNode.isHidden = hasCorners
                }
                let bottomStripeInset: CGFloat
                let bottomStripeOffset: CGFloat
                switch neighbors.bottom {
                case .sameSection(false):
                    bottomStripeInset = params.leftInset + 16.0
                    bottomStripeOffset = -separatorHeight
                    strongSelf.bottomStripeNode.isHidden = false
                default:
                    bottomStripeInset = 0.0
                    bottomStripeOffset = 0.0
                    hasBottomCorners = true
                    strongSelf.bottomStripeNode.isHidden = hasCorners
                }

                strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.theme, top: hasTopCorners, bottom: hasBottomCorners, glass: item.systemStyle == .glass) : nil

                strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                strongSelf.maskNode.frame = strongSelf.backgroundNode.frame.insetBy(dx: params.leftInset, dy: 0.0)
                strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layoutSize.width, height: separatorHeight))
                strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height + bottomStripeOffset), size: CGSize(width: layoutSize.width - bottomStripeInset - params.rightInset - separatorRightInset, height: separatorHeight))

                strongSelf.leftTextNode.attributedText = NSAttributedString(string: "\(item.minValue)%", font: Font.regular(13.0), textColor: item.theme.list.itemSecondaryTextColor)
                strongSelf.rightTextNode.attributedText = NSAttributedString(string: "\(item.maxValue)%", font: Font.regular(13.0), textColor: item.theme.list.itemSecondaryTextColor)
                strongSelf.centerTextNode.attributedText = NSAttributedString(string: "\(item.value)%", font: Font.regular(16.0), textColor: item.theme.list.itemPrimaryTextColor)
                strongSelf.centerMeasureTextNode.attributedText = NSAttributedString(string: "\(item.maxValue)%", font: Font.regular(16.0), textColor: item.theme.list.itemPrimaryTextColor)

                let leftTextSize = strongSelf.leftTextNode.updateLayout(CGSize(width: 100.0, height: 100.0))
                let rightTextSize = strongSelf.rightTextNode.updateLayout(CGSize(width: 100.0, height: 100.0))
                let centerTextSize = strongSelf.centerTextNode.updateLayout(CGSize(width: 200.0, height: 100.0))
                let centerMeasureTextSize = strongSelf.centerMeasureTextNode.updateLayout(CGSize(width: 200.0, height: 100.0))

                let sideInset: CGFloat = 18.0
                strongSelf.leftTextNode.frame = CGRect(origin: CGPoint(x: params.leftInset + sideInset, y: 15.0 + verticalInset), size: leftTextSize)
                strongSelf.rightTextNode.frame = CGRect(origin: CGPoint(x: params.width - params.leftInset - sideInset - rightTextSize.width, y: 15.0 + verticalInset), size: rightTextSize)
                strongSelf.centerTextNode.frame = CGRect(origin: CGPoint(x: floor((params.width - centerMeasureTextSize.width) / 2.0), y: 11.0 + verticalInset), size: centerTextSize)

                let sliderInset: CGFloat = 15.0
                let sliderSize = strongSelf.slider.update(
                    transition: .immediate,
                    component: AnyComponent(
                        SliderComponent(
                            content: .continuous(.init(
                                value: strongSelf.sliderPosition(item.value),
                                minValue: nil,
                                valueUpdated: { [weak self] value in
                                    guard let self = self, let item = self.item else {
                                        return
                                    }
                                    let span = CGFloat(item.maxValue - item.minValue)
                                    let percentage = item.minValue + Int32(round(value * span))
                                    self.updateCenterText(percentage)
                                    item.updated(percentage)
                                }
                            )),
                            useNative: true,
                            trackBackgroundColor: item.theme.list.itemSwitchColors.frameColor,
                            trackForegroundColor: item.theme.list.itemAccentColor
                        )
                    ),
                    environment: {},
                    containerSize: CGSize(width: params.width - params.leftInset - params.rightInset - sliderInset * 2.0, height: 44.0)
                )
                if let sliderView = strongSelf.slider.view {
                    if sliderView.superview == nil {
                        strongSelf.view.addSubview(sliderView)
                    }
                    sliderView.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((params.width - sliderSize.width) / 2.0), y: 36.0 + verticalInset), size: sliderSize)
                }
            })
        }
    }

    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }

    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }

    private func updateCenterText(_ value: Int32) {
        guard let item = self.item, let params = self.layoutParams else {
            return
        }
        var verticalInset: CGFloat = 0.0
        if case .glass = item.systemStyle {
            verticalInset = 4.0
        }
        self.centerTextNode.attributedText = NSAttributedString(string: "\(value)%", font: Font.regular(16.0), textColor: item.theme.list.itemPrimaryTextColor)
        let centerTextSize = self.centerTextNode.updateLayout(CGSize(width: 200.0, height: 100.0))
        let centerMeasureTextSize = self.centerMeasureTextNode.updateLayout(CGSize(width: 200.0, height: 100.0))
        self.centerTextNode.frame = CGRect(origin: CGPoint(x: floor((params.width - centerMeasureTextSize.width) / 2.0), y: 11.0 + verticalInset), size: centerTextSize)
    }
}
