import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import NagramSettings

// MARK: NAGRAM — 文本样式编辑页顶部的预览看板：按当前顺序和开关画出常驻条与键盘面板。
final class NagramTextStylePreviewItem: ListViewItem, ItemListItem {
    struct Style: Equatable {
        let id: NagramTextStyleMenuItemId
        let title: String
    }

    let theme: PresentationTheme
    let barTitle: String
    let panelTitle: String
    let emptyText: String
    let styles: [Style]
    let showsBar: Bool
    let showsPanel: Bool
    let sectionId: ItemListSectionId

    init(theme: PresentationTheme, barTitle: String, panelTitle: String, emptyText: String, styles: [Style], showsBar: Bool, showsPanel: Bool, sectionId: ItemListSectionId) {
        self.theme = theme
        self.barTitle = barTitle
        self.panelTitle = panelTitle
        self.emptyText = emptyText
        self.styles = styles
        self.showsBar = showsBar
        self.showsPanel = showsPanel
        self.sectionId = sectionId
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = NagramTextStylePreviewItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? NagramTextStylePreviewItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async {
                        completion(layout, { _ in apply() })
                    }
                }
            }
        }
    }
}

private enum NagramTextStylePreviewMetrics {
    static let sideInset: CGFloat = 16.0
    static let topInset: CGFloat = 14.0
    static let bottomInset: CGFloat = 16.0
    static let captionHeight: CGFloat = 18.0
    static let captionSpacing: CGFloat = 8.0
    static let sectionSpacing: CGFloat = 18.0
    static let barHeight: CGFloat = 40.0
    static let tileHeight: CGFloat = 68.0
    static let tileSpacing: CGFloat = 6.0
    static let emptyHeight: CGFloat = 40.0

    static func columns(width: CGFloat) -> Int {
        return width >= 390.0 ? 5 : 4
    }

    static func height(styleCount: Int, width: CGFloat) -> CGFloat {
        var height = self.topInset + self.captionHeight + self.captionSpacing + self.barHeight + self.sectionSpacing + self.captionHeight + self.captionSpacing
        if styleCount == 0 {
            height += self.emptyHeight
        } else {
            let rows = Int(ceil(Double(styleCount) / Double(self.columns(width: width))))
            height += CGFloat(rows) * self.tileHeight + CGFloat(max(0, rows - 1)) * self.tileSpacing
        }
        return height + self.bottomInset
    }
}

func nagramTextStyleGlyph(_ id: NagramTextStyleMenuItemId, color: UIColor, fontSize: CGFloat) -> NSAttributedString {
    let font: UIFont
    switch id {
    case .bold:
        font = UIFont.boldSystemFont(ofSize: fontSize)
    case .italic:
        font = UIFont.italicSystemFont(ofSize: fontSize)
    case .code:
        font = UIFont.systemFont(ofSize: fontSize * 0.7, weight: .semibold)
    case .monospace:
        font = Font.monospace(fontSize)
    default:
        font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
    }
    var attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    switch id {
    case .underline:
        attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
    case .strikethrough:
        attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
    default:
        break
    }
    return NSAttributedString(string: id.glyph, attributes: attributes)
}

private final class NagramTextStylePreviewItemNode: ListViewItemNode, ItemListItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode
    private let contentView = UIView()

    private var item: NagramTextStylePreviewItem?

    var tag: ItemListItemTag? {
        return nil
    }

    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
        self.maskNode = ASImageNode()

        super.init(layerBacked: false)

        self.contentView.isUserInteractionEnabled = false
    }

    override func didLoad() {
        super.didLoad()
        self.view.addSubview(self.contentView)
    }

    func asyncLayout() -> (_ item: NagramTextStylePreviewItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params, neighbors in
            let separatorHeight = UIScreenPixel
            let contentWidth = params.width - params.leftInset - params.rightInset - NagramTextStylePreviewMetrics.sideInset * 2.0
            let contentSize = CGSize(width: params.width, height: NagramTextStylePreviewMetrics.height(styleCount: item.styles.count, width: contentWidth))
            let insets = itemListNeighborsGroupedInsets(neighbors, params)
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)

            return (layout, { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.item = item

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
                switch neighbors.bottom {
                case .sameSection(false):
                    strongSelf.bottomStripeNode.isHidden = false
                default:
                    hasBottomCorners = true
                    strongSelf.bottomStripeNode.isHidden = hasCorners
                }
                strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.theme, top: hasTopCorners, bottom: hasBottomCorners, glass: true) : nil

                strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                strongSelf.maskNode.frame = strongSelf.backgroundNode.frame.insetBy(dx: params.leftInset, dy: 0.0)
                strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: separatorHeight))
                strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: contentSize.height - separatorHeight), size: CGSize(width: params.width, height: separatorHeight))

                strongSelf.contentView.frame = CGRect(x: params.leftInset + NagramTextStylePreviewMetrics.sideInset, y: 0.0, width: contentWidth, height: contentSize.height)
                strongSelf.rebuildContent(item: item, width: contentWidth)
            })
        }
    }

    private func rebuildContent(item: NagramTextStylePreviewItem, width: CGFloat) {
        for subview in self.contentView.subviews {
            subview.removeFromSuperview()
        }
        let theme = item.theme
        let foregroundColor = theme.list.itemPrimaryTextColor
        let secondaryColor = theme.list.itemSecondaryTextColor
        let fillColor = theme.list.itemInputField.backgroundColor
        let disabledAlpha: CGFloat = 0.35

        var y = NagramTextStylePreviewMetrics.topInset

        let addCaption: (String) -> Void = { text in
            let label = UILabel(frame: CGRect(x: 0.0, y: y, width: width, height: NagramTextStylePreviewMetrics.captionHeight))
            label.attributedText = NSAttributedString(string: text, font: Font.medium(13.0), textColor: secondaryColor)
            self.contentView.addSubview(label)
            y += NagramTextStylePreviewMetrics.captionHeight + NagramTextStylePreviewMetrics.captionSpacing
        }

        addCaption(item.barTitle)
        let barView = UIView(frame: CGRect(x: 0.0, y: y, width: width, height: NagramTextStylePreviewMetrics.barHeight))
        barView.backgroundColor = fillColor
        barView.layer.cornerRadius = NagramTextStylePreviewMetrics.barHeight * 0.5
        barView.alpha = item.showsBar ? 1.0 : disabledAlpha
        self.contentView.addSubview(barView)
        if item.styles.isEmpty {
            let label = UILabel(frame: barView.bounds)
            label.textAlignment = .center
            label.attributedText = NSAttributedString(string: item.emptyText, font: Font.regular(13.0), textColor: secondaryColor)
            barView.addSubview(label)
        } else {
            let barInset: CGFloat = 6.0
            let step = (width - barInset * 2.0) / CGFloat(item.styles.count)
            for (index, style) in item.styles.enumerated() {
                let label = UILabel(frame: CGRect(x: floorToScreenPixels(barInset + step * CGFloat(index)), y: 0.0, width: floorToScreenPixels(step), height: NagramTextStylePreviewMetrics.barHeight))
                label.textAlignment = .center
                label.attributedText = nagramTextStyleGlyph(style.id, color: foregroundColor, fontSize: 17.0)
                barView.addSubview(label)
            }
        }
        y += NagramTextStylePreviewMetrics.barHeight + NagramTextStylePreviewMetrics.sectionSpacing

        addCaption(item.panelTitle)
        guard !item.styles.isEmpty else {
            let label = UILabel(frame: CGRect(x: 0.0, y: y, width: width, height: NagramTextStylePreviewMetrics.emptyHeight))
            label.textAlignment = .center
            label.alpha = item.showsPanel ? 1.0 : disabledAlpha
            label.attributedText = NSAttributedString(string: item.emptyText, font: Font.regular(13.0), textColor: secondaryColor)
            self.contentView.addSubview(label)
            return
        }
        let columns = NagramTextStylePreviewMetrics.columns(width: width)
        let spacing = NagramTextStylePreviewMetrics.tileSpacing
        let tileWidth = floor((width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        let rows = Int(ceil(Double(item.styles.count) / Double(columns)))
        for (index, style) in item.styles.enumerated() {
            let row = index / columns
            let column = index % columns
            let itemsInRow = row == rows - 1 ? item.styles.count - row * columns : columns
            let rowWidth = CGFloat(itemsInRow) * tileWidth + CGFloat(itemsInRow - 1) * spacing
            let tileFrame = CGRect(x: floor((width - rowWidth) * 0.5) + CGFloat(column) * (tileWidth + spacing), y: y + CGFloat(row) * (NagramTextStylePreviewMetrics.tileHeight + spacing), width: tileWidth, height: NagramTextStylePreviewMetrics.tileHeight)
            let tileView = UIView(frame: tileFrame)
            tileView.alpha = item.showsPanel ? 1.0 : disabledAlpha
            self.contentView.addSubview(tileView)

            let iconSize = CGSize(width: 46.0, height: 36.0)
            let iconView = UIView(frame: CGRect(x: floor((tileWidth - iconSize.width) * 0.5), y: 4.0, width: iconSize.width, height: iconSize.height))
            iconView.backgroundColor = fillColor
            iconView.layer.cornerRadius = 18.0
            tileView.addSubview(iconView)
            let iconLabel = UILabel(frame: iconView.bounds)
            iconLabel.textAlignment = .center
            iconLabel.attributedText = nagramTextStyleGlyph(style.id, color: foregroundColor, fontSize: 20.0)
            iconView.addSubview(iconLabel)

            let titleLabel = UILabel(frame: CGRect(x: 2.0, y: iconView.frame.maxY + 6.0, width: tileWidth - 4.0, height: 16.0))
            titleLabel.textAlignment = .center
            titleLabel.adjustsFontSizeToFitWidth = true
            titleLabel.minimumScaleFactor = 0.72
            titleLabel.attributedText = NSAttributedString(string: style.title, font: Font.regular(11.0), textColor: foregroundColor)
            tileView.addSubview(titleLabel)
        }
    }

    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }

    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
}
