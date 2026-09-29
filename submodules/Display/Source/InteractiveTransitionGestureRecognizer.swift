import Foundation
import UIKit

private enum HorizontalGestures {
    case none
    case some
    case strict
}

private func hasHorizontalGestures(_ view: UIView, point: CGPoint?) -> HorizontalGestures {
    if let disablesInteractiveTransitionGestureRecognizerNow = view.disablesInteractiveTransitionGestureRecognizerNow, disablesInteractiveTransitionGestureRecognizerNow() {
        return .strict
    }
    
    if view.disablesInteractiveTransitionGestureRecognizer {
        return .some
    }
    
    if let point = point, let test = view.interactiveTransitionGestureRecognizerTest, test(point) {
        return .some
    }
    
    if let view = view as? ListViewBackingView {
        let transform = view.transform
        let angle: Double = Double(atan2f(Float(transform.b), Float(transform.a)))
        let term1: Double = abs(angle - Double.pi / 2.0)
        let term2: Double = abs(angle + Double.pi / 2.0)
        let term3: Double = abs(angle - Double.pi * 3.0 / 2.0)
        if term1 < 0.001 || term2 < 0.001 || term3 < 0.001 {
            return .some
        }
    }
    
    if let superview = view.superview {
        return hasHorizontalGestures(superview, point: point != nil ? view.convert(point!, to: superview) : nil)
    } else {
        return .none
    }
}

public struct InteractiveTransitionGestureRecognizerDirections: OptionSet {
    public var rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let leftEdge = InteractiveTransitionGestureRecognizerDirections(rawValue: 1 << 2)
    public static let rightEdge = InteractiveTransitionGestureRecognizerDirections(rawValue: 1 << 3)
    public static let leftCenter = InteractiveTransitionGestureRecognizerDirections(rawValue: 1 << 0)
    public static let rightCenter = InteractiveTransitionGestureRecognizerDirections(rawValue: 1 << 1)
    public static let down = InteractiveTransitionGestureRecognizerDirections(rawValue: 1 << 4)
    
    public static let left: InteractiveTransitionGestureRecognizerDirections = [.leftEdge, .leftCenter]
    public static let right: InteractiveTransitionGestureRecognizerDirections = [.rightEdge, .rightCenter]
}

public enum InteractiveTransitionGestureRecognizerEdgeWidth {
    case constant(CGFloat)
    case widthMultiplier(factor: CGFloat, min: CGFloat, max: CGFloat)
}

public enum InteractiveTransitionGestureRecognizerDirectionMode {
    case horizontal
    case vertical
}

public class InteractiveTransitionGestureRecognizer: UIPanGestureRecognizer {
    private let edgeWidth: InteractiveTransitionGestureRecognizerEdgeWidth
    private let allowedDirections: (CGPoint) -> InteractiveTransitionGestureRecognizerDirections

    private var validatedGesture = false
    private var firstLocation: CGPoint = CGPoint()
    private var currentAllowedDirections: InteractiveTransitionGestureRecognizerDirections = []
    private var directionCheckpoint: CGPoint = CGPoint()

    /// Axis of a claimed gesture, re-evaluated continuously from `directionCheckpoint`.
    /// Vertical has priority: a claimed gesture switches to `.vertical` as soon as the
    /// post-claim drift is clearly vertical, and can switch back while the finger is down.
    public private(set) var directionMode: InteractiveTransitionGestureRecognizerDirectionMode = .horizontal
    
    public init(target: Any?, action: Selector?, allowedDirections: @escaping (CGPoint) -> InteractiveTransitionGestureRecognizerDirections, edgeWidth: InteractiveTransitionGestureRecognizerEdgeWidth = .constant(16.0)) {
        self.allowedDirections = allowedDirections
        self.edgeWidth = edgeWidth
        
        super.init(target: target, action: action)
        
        self.maximumNumberOfTouches = 1
        self.delaysTouchesBegan = false
    }
    
    override public func reset() {
        super.reset()

        self.validatedGesture = false
        self.currentAllowedDirections = []
        self.directionCheckpoint = CGPoint()
        self.directionMode = .horizontal
    }

    public func cancel() {
        self.state = .cancelled
    }
    
    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        let touch = touches.first!
        let point = touch.location(in: self.view)
        
        var allowedDirections = self.allowedDirections(point)
        if allowedDirections.isEmpty {
            self.state = .failed
            return
        }
        
        super.touchesBegan(touches, with: event)
        
        self.firstLocation = point
        
        if let target = self.view?.hitTest(self.firstLocation, with: event) {
            let horizontalGestures = hasHorizontalGestures(target, point: self.view?.convert(self.firstLocation, to: target))
            switch horizontalGestures {
            case .some, .strict:
                if allowedDirections.contains(.down) {
                } else {
                    if case .strict = horizontalGestures {
                        allowedDirections = []
                    } else if allowedDirections.contains(.leftEdge) || allowedDirections.contains(.rightEdge) {
                        allowedDirections.remove(.leftCenter)
                        allowedDirections.remove(.rightCenter)
                    }
                }
            case .none:
                break
            }
        }
        
        if allowedDirections.isEmpty {
            self.state = .failed
        } else {
            self.currentAllowedDirections = allowedDirections
        }
    }
    
    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        let location = touches.first!.location(in: self.view)
        let translation = CGPoint(x: location.x - self.firstLocation.x, y: location.y - self.firstLocation.y)
        
        let absTranslationX: CGFloat = abs(translation.x)
        let absTranslationY: CGFloat = abs(translation.y)
        
        let size = self.view?.bounds.size ?? CGSize()
        
        //print("moved: \(CFAbsoluteTimeGetCurrent()) absTranslationX: \(absTranslationX) absTranslationY: \(absTranslationY)")

        if self.currentAllowedDirections.contains(.down) {
            if !self.validatedGesture {
                let totalMovement = sqrt(absTranslationX * absTranslationX + absTranslationY * absTranslationY)
                if totalMovement > 10.0 {
                    // Force dominant direction after 10pt movement
                    if absTranslationY >= absTranslationX {
                        self.validatedGesture = true
                    } else {
                        self.state = .failed
                    }
                } else if absTranslationX > 2.0 && absTranslationX > absTranslationY * 2.0 {
                    self.state = .failed
                } else if absTranslationY > 2.0 && absTranslationX * 2.0 < absTranslationY {
                    self.validatedGesture = true
                }
            }
        } else {
            let edgeWidth: CGFloat
            switch self.edgeWidth {
            case let .constant(value):
                edgeWidth = value
            case let .widthMultiplier(factor, minValue, maxValue):
                edgeWidth = max(minValue, min(size.width * factor, maxValue))
            }

            if !self.validatedGesture {
                if self.firstLocation.x < edgeWidth && !self.currentAllowedDirections.contains(.rightEdge) {
                    self.state = .failed
                    return
                }
                if self.firstLocation.x > size.width - edgeWidth && !self.currentAllowedDirections.contains(.leftEdge) {
                    self.state = .failed
                    return
                }

                if self.currentAllowedDirections.contains(.rightEdge) && self.firstLocation.x < edgeWidth {
                    self.validatedGesture = true
                    self.directionCheckpoint = location
                } else if self.currentAllowedDirections.contains(.leftEdge) && self.firstLocation.x > size.width - edgeWidth {
                    self.validatedGesture = true
                    self.directionCheckpoint = location
                } else if !self.currentAllowedDirections.contains(.leftCenter) && translation.x < 0.0 {
                    self.state = .failed
                } else if !self.currentAllowedDirections.contains(.rightCenter) && translation.x > 0.0 {
                    self.state = .failed
                } else {
                    // Vertical has priority: give up on any clearly vertical movement,
                    // claim the gesture only on clearly horizontal movement, and let
                    // the 10pt forced decision fall through to vertical on ties.
                    let totalMovement = sqrt(absTranslationX * absTranslationX + absTranslationY * absTranslationY)
                    if absTranslationY > 2.0 && absTranslationY > absTranslationX * 1.2 {
                        self.state = .failed
                    } else if absTranslationX > 6.0 && absTranslationX > absTranslationY * 2.0 {
                        self.validatedGesture = true
                        self.directionCheckpoint = location
                    } else if totalMovement > 10.0 {
                        // Force dominant direction after 10pt movement
                        if absTranslationX > absTranslationY * 1.5 {
                            self.validatedGesture = true
                            self.directionCheckpoint = location
                        } else {
                            self.state = .failed
                        }
                    }
                }
            } else {
                // A claimed gesture is not locked to horizontal for the rest of the
                // touch. Before the pan has begun, clear vertical evidence fails this
                // recognizer outright so the vertical scroll takes over the gesture;
                // after it has begun, the axis can still flip in both directions.
                if self.state == .possible {
                    if absTranslationY > 2.0 && absTranslationY > absTranslationX * 1.2 {
                        self.validatedGesture = false
                        self.state = .failed
                        return
                    }
                } else {
                    self.updateDirectionMode(location: location)
                }
            }
        }

        if self.validatedGesture {
            super.touchesMoved(touches, with: event)
        }
    }

    private func updateDirectionMode(location: CGPoint) {
        let absDeltaX: CGFloat = abs(location.x - self.directionCheckpoint.x)
        let absDeltaY: CGFloat = abs(location.y - self.directionCheckpoint.y)

        switch self.directionMode {
        case .horizontal:
            if absDeltaY > 20.0 && absDeltaY > absDeltaX * 1.5 {
                self.directionMode = .vertical
                self.directionCheckpoint = location
            }
        case .vertical:
            if absDeltaX > 12.0 && absDeltaX > absDeltaY * 2.0 {
                self.directionMode = .horizontal
                self.directionCheckpoint = location
            }
        }
    }
}
