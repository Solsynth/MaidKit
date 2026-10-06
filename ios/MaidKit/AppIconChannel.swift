import Flutter
import UIKit

/// Bridges alternate app icon switching (`UIApplication.setAlternateIconName`)
/// to the Flutter side over the `dev.solsynth.maidKit/app_icon` channel.
final class AppIconChannel {
    static let channelName = "dev.solsynth.maidKit/app_icon"

    private init() {}

    static func install(binaryMessenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: binaryMessenger
        )
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "getIconState":
                // Platform-channel handlers run on the main thread.
                let application = UIApplication.shared
                result([
                    "supported": application.supportsAlternateIcons,
                    "current": application.alternateIconName as Any,
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
                // `setAlternateIconName` and its completion handler both run on
                // the main thread, so calling `result` from the completion is safe.
                UIApplication.shared.setAlternateIconName(name) { error in
                    if let error {
                        result(FlutterError(
                            code: "SET_ALTERNATE_ICON_FAILED",
                            message: error.localizedDescription,
                            details: nil
                        ))
                    } else {
                        result(nil)
                    }
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
