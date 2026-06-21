import AppKit

struct BrowserAttachRequest {
    let surfaceKey: LifecycleSurfaceKey
    let viewID: String
    let extensionID: String
    let profileID: UUID?
    let rect: NSRect
    let visible: Bool
    let url: String?
}

@MainActor
final class ExtensionBrowserOverlayRegistry {
    static let shared = ExtensionBrowserOverlayRegistry()

    private final class Surface {
        weak var container: NSView?
        let stateSink: (String, ExtensionBrowserState) -> Void
        var overlays: [String: ExtensionBrowserOverlay] = [:]

        init(container: NSView, stateSink: @escaping (String, ExtensionBrowserState) -> Void) {
            self.container = container
            self.stateSink = stateSink
        }
    }

    private var surfaces: [LifecycleSurfaceKey: Surface] = [:]

    func registerSurface(
        _ key: LifecycleSurfaceKey,
        container: NSView,
        stateSink: @escaping (String, ExtensionBrowserState) -> Void
    ) {
        surfaces[key] = Surface(container: container, stateSink: stateSink)
    }

    func unregisterSurface(_ key: LifecycleSurfaceKey) {
        guard let surface = surfaces.removeValue(forKey: key) else { return }
        for overlay in surface.overlays.values {
            overlay.teardown()
        }
    }

    @discardableResult
    func attach(_ request: BrowserAttachRequest) throws -> ExtensionBrowserState {
        guard let surface = surfaces[request.surfaceKey], let container = surface.container else {
            throw APIError.underlying("browser surface not ready")
        }
        let viewID = request.viewID
        if let existing = surface.overlays[viewID] {
            existing.teardown()
        }
        let overlay = ExtensionBrowserOverlay(
            viewID: viewID,
            extensionID: request.extensionID,
            profileID: request.profileID
        )
        overlay.onStateChange = { [weak surface] state in
            surface?.stateSink(viewID, state)
        }
        container.addSubview(overlay.wrapper)
        overlay.setFrame(flip(request.rect, in: container), visible: request.visible)
        surface.overlays[viewID] = overlay
        if let url = request.url, !url.isEmpty {
            overlay.load(url)
        }
        return overlay.state
    }

    func updateRect(surfaceKey: LifecycleSurfaceKey, viewID: String, rect: NSRect, visible: Bool) {
        guard let surface = surfaces[surfaceKey], let container = surface.container,
              let overlay = surface.overlays[viewID]
        else { return }
        overlay.setFrame(flip(rect, in: container), visible: visible)
    }

    func setVisible(surfaceKey: LifecycleSurfaceKey, viewID: String, visible: Bool) {
        overlay(surfaceKey, viewID)?.setVisible(visible)
    }

    func navigate(surfaceKey: LifecycleSurfaceKey, viewID: String, url: String) {
        overlay(surfaceKey, viewID)?.load(url)
    }

    func command(surfaceKey: LifecycleSurfaceKey, viewID: String, command: String) {
        guard let overlay = overlay(surfaceKey, viewID) else { return }
        switch command {
        case "back": overlay.back()
        case "forward": overlay.forward()
        case "reload": overlay.reload()
        case "stop": overlay.stop()
        default: break
        }
    }

    func find(surfaceKey: LifecycleSurfaceKey, viewID: String, text: String) {
        overlay(surfaceKey, viewID)?.find(text)
    }

    func executeJS(surfaceKey: LifecycleSurfaceKey, viewID: String, source: String) async throws -> Any? {
        guard let overlay = overlay(surfaceKey, viewID) else {
            throw APIError.underlying("browser view not found")
        }
        return try await overlay.executeJS(source)
    }

    func detach(surfaceKey: LifecycleSurfaceKey, viewID: String) {
        guard let surface = surfaces[surfaceKey],
              let overlay = surface.overlays.removeValue(forKey: viewID)
        else { return }
        overlay.teardown()
    }

    func disableAll() {
        for surface in surfaces.values {
            for overlay in surface.overlays.values {
                overlay.teardown()
            }
            surface.overlays.removeAll()
        }
    }

    private func overlay(_ surfaceKey: LifecycleSurfaceKey, _ viewID: String) -> ExtensionBrowserOverlay? {
        guard BrowserPreferences.isEmbedEnabled else { return nil }
        return surfaces[surfaceKey]?.overlays[viewID]
    }

    private func flip(_ rect: NSRect, in container: NSView) -> NSRect {
        guard !container.isFlipped else { return rect }
        return NSRect(
            x: rect.origin.x,
            y: container.bounds.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
