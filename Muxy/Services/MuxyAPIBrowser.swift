import AppKit

extension MuxyAPI {
    @MainActor
    enum Browser {
        static func attach(
            extensionID: String,
            surfaceKey: LifecycleSurfaceKey?,
            args: [String: Any]
        ) async throws -> [String: Any] {
            guard BrowserPreferences.isEmbedEnabled else {
                throw APIError.underlying("built-in browser is disabled")
            }
            guard let surfaceKey else {
                throw APIError.underlying("browser views require a webview surface")
            }
            try await gateEmbedConsent(extensionID: extensionID)
            let viewID = try requireString(args, "viewID")
            let rect = try parseRect(args)
            let visible = (args["visible"] as? Bool) ?? true
            let url = args["url"] as? String
            let profileID = resolveProfileID(extensionID: extensionID, args: args)
            let state = try ExtensionBrowserOverlayRegistry.shared.attach(
                BrowserAttachRequest(
                    surfaceKey: surfaceKey,
                    viewID: viewID,
                    extensionID: extensionID,
                    profileID: profileID,
                    rect: rect,
                    visible: visible,
                    url: url
                )
            )
            return stateDict(state)
        }

        static func updateRect(surfaceKey: LifecycleSurfaceKey?, args: [String: Any]) throws {
            guard let surfaceKey else { return }
            let viewID = try requireString(args, "viewID")
            let rect = try parseRect(args)
            let visible = (args["visible"] as? Bool) ?? true
            ExtensionBrowserOverlayRegistry.shared.updateRect(
                surfaceKey: surfaceKey,
                viewID: viewID,
                rect: rect,
                visible: visible
            )
        }

        static func setVisible(surfaceKey: LifecycleSurfaceKey?, args: [String: Any]) throws {
            guard let surfaceKey else { return }
            let viewID = try requireString(args, "viewID")
            let visible = (args["visible"] as? Bool) ?? true
            ExtensionBrowserOverlayRegistry.shared.setVisible(
                surfaceKey: surfaceKey,
                viewID: viewID,
                visible: visible
            )
        }

        static func navigate(surfaceKey: LifecycleSurfaceKey?, args: [String: Any]) throws {
            guard let surfaceKey else { return }
            let viewID = try requireString(args, "viewID")
            let url = try requireString(args, "url")
            ExtensionBrowserOverlayRegistry.shared.navigate(surfaceKey: surfaceKey, viewID: viewID, url: url)
        }

        static func command(surfaceKey: LifecycleSurfaceKey?, command: String, args: [String: Any]) throws {
            guard let surfaceKey else { return }
            let viewID = try requireString(args, "viewID")
            ExtensionBrowserOverlayRegistry.shared.command(surfaceKey: surfaceKey, viewID: viewID, command: command)
        }

        static func find(surfaceKey: LifecycleSurfaceKey?, args: [String: Any]) throws {
            guard let surfaceKey else { return }
            let viewID = try requireString(args, "viewID")
            let text = (args["text"] as? String) ?? ""
            ExtensionBrowserOverlayRegistry.shared.find(surfaceKey: surfaceKey, viewID: viewID, text: text)
        }

        static func executeJS(surfaceKey: LifecycleSurfaceKey?, args: [String: Any]) async throws -> Any {
            guard let surfaceKey else {
                throw APIError.underlying("browser views require a webview surface")
            }
            let viewID = try requireString(args, "viewID")
            let source = try requireString(args, "source")
            let result = try await ExtensionBrowserOverlayRegistry.shared.executeJS(
                surfaceKey: surfaceKey,
                viewID: viewID,
                source: source
            )
            return result ?? NSNull()
        }

        static func detach(surfaceKey: LifecycleSurfaceKey?, args: [String: Any]) throws {
            guard let surfaceKey else { return }
            let viewID = try requireString(args, "viewID")
            ExtensionBrowserOverlayRegistry.shared.detach(surfaceKey: surfaceKey, viewID: viewID)
        }

        static func profilesList(extensionID: String) -> [String] {
            ExtensionBrowserProfileStore.shared.list(extensionID: extensionID)
        }

        static func profilesCreate(extensionID: String, args: [String: Any]) throws {
            let key = try requireString(args, "profile")
            ExtensionBrowserProfileStore.shared.ensure(extensionID: extensionID, key: key)
        }

        static func profilesDelete(extensionID: String, args: [String: Any]) async throws {
            let key = try requireString(args, "profile")
            await ExtensionBrowserProfileStore.shared.delete(extensionID: extensionID, key: key)
        }

        static func profilesClear(extensionID: String, args: [String: Any]) async throws {
            let key = try requireString(args, "profile")
            await ExtensionBrowserProfileStore.shared.clear(extensionID: extensionID, key: key)
        }

        static func profilesSetCookies(extensionID: String, args: [String: Any]) async throws {
            let key = try requireString(args, "profile")
            let cookies = parseCookies(args["cookies"])
            await ExtensionBrowserProfileStore.shared.setCookies(
                extensionID: extensionID,
                key: key,
                cookies: cookies
            )
        }

        private static func resolveProfileID(extensionID: String, args: [String: Any]) -> UUID? {
            guard let key = args["profile"] as? String, !key.isEmpty else { return nil }
            ExtensionBrowserProfileStore.shared.ensure(extensionID: extensionID, key: key)
            return ExtensionBrowserProfileStore.shared.profileID(extensionID: extensionID, key: key)
        }

        private static func parseRect(_ args: [String: Any]) throws -> NSRect {
            guard let rect = args["rect"] as? [String: Any] else {
                throw APIError.invalidArguments("missing argument 'rect'")
            }
            let x = doubleValue(rect["x"])
            let y = doubleValue(rect["y"])
            let width = doubleValue(rect["width"])
            let height = doubleValue(rect["height"])
            return NSRect(x: x, y: y, width: width, height: height)
        }

        private static func parseCookies(_ raw: Any?) -> [BrowserCookie] {
            guard let array = raw as? [[String: Any]] else { return [] }
            return array.compactMap { dict in
                guard let name = dict["name"] as? String,
                      let domain = dict["domain"] as? String
                else { return nil }
                let expires = dict["expires"].flatMap { value -> Date? in
                    let seconds = doubleValue(value)
                    return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
                }
                return BrowserCookie(
                    name: name,
                    value: (dict["value"] as? String) ?? "",
                    domain: domain,
                    path: (dict["path"] as? String) ?? "/",
                    secure: (dict["secure"] as? Bool) ?? false,
                    httpOnly: (dict["httpOnly"] as? Bool) ?? false,
                    expires: expires
                )
            }
        }

        private static func stateDict(_ state: ExtensionBrowserState) -> [String: Any] {
            [
                "url": state.url ?? NSNull(),
                "title": state.title ?? NSNull(),
                "canGoBack": state.canGoBack,
                "canGoForward": state.canGoForward,
                "isLoading": state.isLoading,
                "progress": state.progress,
            ]
        }

        private static func gateEmbedConsent(extensionID: String) async throws {
            let request = ExtensionConsentRequestBuilder.make(
                extensionID: extensionID,
                verb: .browserEmbed,
                payload: .browser,
                source: "browser"
            )
            let decision = await ExtensionConsentService.shared.gate(request)
            guard decision == .allow else {
                throw APIError.consentDenied(verb: "browser.embed")
            }
        }

        private static func requireString(_ args: [String: Any], _ key: String) throws -> String {
            guard let value = args[key] as? String, !value.isEmpty else {
                throw APIError.invalidArguments("missing argument '\(key)'")
            }
            return value
        }

        private static func doubleValue(_ value: Any?) -> Double {
            if let double = value as? Double { return double }
            if let int = value as? Int { return Double(int) }
            if let number = value as? NSNumber { return number.doubleValue }
            return 0
        }
    }
}
