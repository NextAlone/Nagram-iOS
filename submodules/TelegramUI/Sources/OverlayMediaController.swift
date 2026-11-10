import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import AccountContext
import AVKit

public final class OverlayMediaControllerImpl: ViewController, OverlayMediaController {
    private var controllerNode: OverlayMediaControllerNode {
        return self.displayNode as! OverlayMediaControllerNode
    }
    
    public var updatePossibleEmbeddingItem: ((OverlayMediaControllerEmbeddingItem?) -> Void)?
    public var embedPossibleEmbeddingItem: ((OverlayMediaControllerEmbeddingItem) -> Bool)?

    private var pictureInPictureContainer: ASDisplayNode?
    private var pictureInPictureContent: PictureInPictureContent?
    
    // MARK: NAGRAM - Reads the bars of the screens under the overlay; set by the app for its root navigation controller.
    public var barObstructionProvider: (() -> NagramOverlayObstruction?)? {
        didSet {
            self.updateBarObstruction(transition: .immediate)
        }
    }
    
    public init() {
        super.init(navigationBarPresentationData: nil)
        
        self.statusBar.statusBarStyle = .Ignore
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func loadDisplayNode() {
        self.displayNode = OverlayMediaControllerNode(updatePossibleEmbeddingItem: { [weak self] item in
            self?.updatePossibleEmbeddingItem?(item)
        }, embedPossibleEmbeddingItem: { [weak self] item in
            return self?.embedPossibleEmbeddingItem?(item) ?? false
        })
        self.displayNodeDidLoad()
    }
    
    public var hasNodes: Bool {
        return self.controllerNode.hasNodes
    }
    
    public func addNode(_ node: OverlayMediaItemNode, customTransition: Bool) {
        // MARK: NAGRAM - Read the bars before the first item is placed.
        if !self.controllerNode.hasNodes {
            self.updateBarObstruction(transition: .immediate)
        }
        self.controllerNode.addNode(node, customTransition: customTransition)
        self.updateBarTracking() // MARK: NAGRAM
    }
    
    public func removeNode(_ node: OverlayMediaItemNode, customTransition: Bool) {
        self.controllerNode.removeNode(node, customTransition: customTransition)
        self.updateBarTracking() // MARK: NAGRAM
    }
    
    // MARK: NAGRAM - Follow the bars only while an item is shown.
    private func updateBarTracking() {
        let tracker = NagramOverlayBarTracker.shared
        let isActive = self.controllerNode.hasNodes
        if isActive {
            tracker.invalidated = { [weak self] transition in
                self?.updateBarObstruction(transition: transition)
            }
        }
        tracker.isActive = isActive
    }
    
    // MARK: NAGRAM
    private func updateBarObstruction(transition: ContainedViewLayoutTransition) {
        guard self.isNodeLoaded else {
            return
        }
        self.controllerNode.updateBarObstruction(self.barObstructionProvider?(), transition: transition)
    }

    public func setPictureInPictureContent(content: PictureInPictureContent, absoluteRect: CGRect) {
        if self.pictureInPictureContainer == nil {
            let pictureInPictureContainer = ASDisplayNode()
            pictureInPictureContainer.clipsToBounds = false
            self.pictureInPictureContainer = pictureInPictureContainer
            self.controllerNode.addSubnode(pictureInPictureContainer)
        }
        self.pictureInPictureContainer?.clipsToBounds = false
        self.pictureInPictureContent = content
        self.pictureInPictureContainer?.addSubnode(content.videoNode)
    }

    public func setPictureInPictureContentHidden(content: PictureInPictureContent, isHidden value: Bool) {
        if self.pictureInPictureContent === content {
            self.pictureInPictureContainer?.clipsToBounds = value
        }
    }

    public func removePictureInPictureContent(content: PictureInPictureContent) {
        if self.pictureInPictureContent === content {
            self.pictureInPictureContent = nil
            content.videoNode.removeFromSupernode()
        }
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        let updatedLayout = ContainerViewLayout(size: layout.size, metrics: layout.metrics, deviceMetrics: layout.deviceMetrics, intrinsicInsets: UIEdgeInsets(top: (layout.statusBarHeight ?? 0.0) + 44.0, left: layout.intrinsicInsets.left, bottom: layout.intrinsicInsets.bottom, right: layout.intrinsicInsets.right), safeInsets: layout.safeInsets, reservedCorners: layout.reservedCorners, division: layout.division, additionalInsets: layout.additionalInsets, statusBarHeight: layout.statusBarHeight, inputHeight: layout.inputHeight, inputHeightIsInteractivellyChanging: layout.inputHeightIsInteractivellyChanging, inVoiceOver: layout.inVoiceOver, presentedInFormSheet: layout.presentedInFormSheet)
        // MARK: NAGRAM - The window lays out the root controller first, so its bars are already where this layout goes.
        if self.controllerNode.hasNodes {
            self.controllerNode.barObstruction = self.barObstructionProvider?()
        }
        self.controllerNode.containerLayoutUpdated(updatedLayout, transition: transition)
    }
}
