import Cocoa
import FlutterMacOS

/// Bridges runtime app icon switching on macOS over the
/// `dev.solsynth.maidKit/app_icon` channel.
///
/// macOS has no public alternate-icon API (`UIApplication.setAlternateIconName`
/// is iOS-only), so this swaps the Dock icon for the running session via
/// `NSApp.applicationIconImage` and persists the choice at the system level
/// with `NSWorkspace.setIcon` — the custom icon stays on the Dock and in
/// Finder for later launches, so no per-launch re-apply is required.
final class AppIconChannel {
  static let channelName = "dev.solsynth.maidKit/app_icon"
  static let storedIconNameKey = "app_icon_name"

  private init() {}

  static func install(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getIconState":
        result([
          "supported": true,
          "current": UserDefaults.standard.string(
            forKey: storedIconNameKey
          ) as Any,
        ])
      case "setAlternateIcon":
        guard let arguments = call.arguments as? [String: Any] else {
          result(FlutterError(
            code: "INVALID_ARGUMENTS",
            message: "Expected a payload with an optional `name` string.",
            details: nil
          ))
          return
        }
        let name = arguments["name"] as? String
        applyIcon(name: name)
        if let name {
          UserDefaults.standard.set(name, forKey: storedIconNameKey)
        } else {
          UserDefaults.standard.removeObject(forKey: storedIconNameKey)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Re-applies the persisted icon choice on launch. No-op when the user
  /// never switched away from the default. Belt-and-suspenders: the icon is
  /// already persisted system-wide by `NSWorkspace.setIcon`, so this only
  /// re-syncs the running session's Dock tile.
  static func applyPersistedIconIfNeeded() {
    guard let name = UserDefaults.standard.string(forKey: storedIconNameKey) else {
      return
    }
    applyIcon(name: name)
  }

  private static func applyIcon(name: String?) {
    let bundlePath = Bundle.main.bundlePath
    if let name, let image = NSImage(named: name) {
      NSApp.applicationIconImage = image
      // Persist at the system level (Finder icon database) so the Dock and
      // Finder keep showing the alternate icon on later launches without
      // re-applying here. Returns false when the bundle is not writable.
      if !NSWorkspace.shared.setIcon(image, forFile: bundlePath, options: []) {
        NSLog("[AppIcon] failed to persist alternate icon: %@", name)
      }
      NSLog("[AppIcon] applied alternate icon: %@", name)
    } else {
      // `applicationIconImage` is null-resettable: nil restores the app's
      // default icon for the running session. Passing nil to `setIcon`
      // removes the custom icon so the bundle default returns.
      NSApp.applicationIconImage = nil
      NSWorkspace.shared.setIcon(nil, forFile: bundlePath, options: [])
      if name != nil {
        NSLog("[AppIcon] icon not found in bundle: %@", name!)
      }
    }
  }
}
