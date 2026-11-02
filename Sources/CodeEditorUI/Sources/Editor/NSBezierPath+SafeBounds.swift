import AppKit

extension NSBezierPath {
    private static let installToken: Void = {
        if let originalBounds = class_getInstanceMethod(
            NSBezierPath.self,
            #selector(getter: NSBezierPath.bounds)
        ),
            let swizzledBounds = class_getInstanceMethod(
                NSBezierPath.self,
                #selector(NSBezierPath.safeBounds)
            )
        {
            method_exchangeImplementations(originalBounds, swizzledBounds)
        }
        if let originalCPB = class_getInstanceMethod(
            NSBezierPath.self,
            #selector(getter: NSBezierPath.controlPointBounds)
        ),
            let swizzledCPB = class_getInstanceMethod(
                NSBezierPath.self,
                #selector(NSBezierPath.safeControlPointBounds)
            )
        {
            method_exchangeImplementations(originalCPB, swizzledCPB)
        }
    }()

    @objc dynamic func safeBounds() -> NSRect {
        if self.isEmpty || self.elementCount == 0 {
            return .zero
        }
        return self.safeBounds()
    }

    @objc dynamic func safeControlPointBounds() -> NSRect {
        if self.isEmpty || self.elementCount == 0 {
            return .zero
        }
        return self.safeControlPointBounds()
    }

    /// Swizzles `bounds` and `controlPointBounds` on `NSBezierPath` so that querying an empty path
    /// returns `.zero` instead of raising an unhandled `NSGenericException` (`No current point for control point bounds`).
    ///
    /// In AppKit, `-[NSBezierPath bounds]` calls `-[NSBezierPath controlPointBounds]`, which throws an
    /// Objective-C exception if the path has 0 elements. Libraries like CodeEditTextView's `EmphasisManager`
    /// call `.bounds` during text rendering without checking `isEmpty`, leading to `SIGABRT` crashes.
    public static func installSafeBoundsWorkaround() {
        _ = installToken
    }
}
