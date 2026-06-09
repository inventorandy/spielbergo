import Flutter
import UIKit

public class SpielbergoPlugin: NSObject, FlutterPlugin {
  private var pendingResult: FlutterResult?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "spielbergo", binaryMessenger: registrar.messenger())
    let instance = SpielbergoPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "pickVideo":
      pickVideo(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func pickVideo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(code: "already_active", message: "Spielbergo video editor is already open.", details: nil))
      return
    }
    guard let presenter = topViewController() else {
      result(FlutterError(code: "no_view_controller", message: "Could not find a view controller to present from.", details: nil))
      return
    }

    let arguments = call.arguments as? [String: Any]
    let recordTimes = arguments?["recordTimes"] as? [String] ?? []
    let defaultRecordTime = arguments?["defaultRecordTime"] as? String
    pendingResult = result

    let editor = SpielbergoVideoEditorViewController(
      recordTimes: recordTimes,
      defaultRecordTime: defaultRecordTime
    )
    editor.modalPresentationStyle = .fullScreen
    editor.onComplete = { [weak self] path in
      self?.pendingResult?(path)
      self?.pendingResult = nil
    }
    presenter.present(editor, animated: true)
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
    var controller = window?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }
}
