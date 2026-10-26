import AppKit

extension NSBezierPath {
    private static let _installToken: Void = {
        if let originalBounds = class_getInstanceMethod(NSBezierPath.self, #selector(getter: NSBezierPath.bounds)),
           let swizzledBounds = class_getInstanceMethod(NSBezierPath.self, #selector(NSBezierPath.safe_bounds)) {
            method_exchangeImplementations(originalBounds, swizzledBounds)
        }
        if let originalCPB = class_getInstanceMethod(NSBezierPath.self, #selector(getter: NSBezierPath.controlPointBounds)),
           let swizzledCPB = class_getInstanceMethod(NSBezierPath.self, #selector(NSBezierPath.safe_controlPointBounds)) {
            method_exchangeImplementations(originalCPB, swizzledCPB)
        }
    }()

    @objc dynamic func safe_bounds() -> NSRect {
        if self.isEmpty || self.elementCount == 0 {
            return .zero
        }
        return self.safe_bounds()
    }

    @objc dynamic func safe_controlPointBounds() -> NSRect {
        if self.isEmpty || self.elementCount == 0 {
            return .zero
        }
        return self.safe_controlPointBounds()
    }

    /// Swizzles `bounds` and `controlPointBounds` on `NSBezierPath` so that querying an empty path
    /// returns `.zero` instead of raising an unhandled `NSGenericException` (`No current point for control point bounds`).
    ///
    /// In AppKit, `-[NSBezierPath bounds]` calls `-[NSBezierPath controlPointBounds]`, which throws an
    /// Objective-C exception if the path has 0 elements. Libraries like CodeEditTextView's `EmphasisManager`
    /// call `.bounds` during text rendering without checking `isEmpty`, leading to `SIGABRT` crashes.
    public static func installSafeBoundsWorkaround() {
        _ = _installToken
    }
}
