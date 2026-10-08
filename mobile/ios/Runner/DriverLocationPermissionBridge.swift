import CoreLocation
import Flutter
import UIKit

final class DriverLocationPermissionBridge: NSObject, CLLocationManagerDelegate {
  static let channelName = "com.denkma.app/driver_location_permission"
  static let upgradePromptKey = "denkma_driver_always_location_prompt_v1"
  private static let noPromptDelay: TimeInterval = 2

  private let manager: CLLocationManager
  private let preferences: UserDefaults
  private let notifications: NotificationCenter
  private let applicationState: () -> UIApplication.State
  private var results: [FlutterResult] = []
  private var requestIssued = false
  private var promptObserved = false
  private var noPromptCheck: DispatchWorkItem?

  init(
    manager: CLLocationManager = CLLocationManager(),
    preferences: UserDefaults = .standard,
    notifications: NotificationCenter = .default,
    applicationState: @escaping () -> UIApplication.State = {
      UIApplication.shared.applicationState
    }
  ) {
    self.manager = manager
    self.preferences = preferences
    self.notifications = notifications
    self.applicationState = applicationState
    super.init()
    manager.delegate = self
    notifications.addObserver(
      self, selector: #selector(willResignActive(_:)),
      name: UIApplication.willResignActiveNotification, object: nil
    )
    notifications.addObserver(
      self, selector: #selector(didBecomeActive(_:)),
      name: UIApplication.didBecomeActiveNotification, object: nil
    )
  }

  deinit {
    noPromptCheck?.cancel()
    notifications.removeObserver(self)
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    let bridge = DriverLocationPermissionBridge()
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "requestAlwaysAuthorization" else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        bridge.requestAlways(result)
      }
    }
  }

  func requestAlways(_ result: @escaping FlutterResult) {
    results.append(result)
    if results.count == 1 { advanceRequest() }
  }

  private func advanceRequest() {
    guard !results.isEmpty, applicationState() == .active else { return }
    let authorization = manager.authorizationStatus
    if authorization == .notDetermined {
      preferences.removeObject(forKey: Self.upgradePromptKey)
    }
    guard authorization == .authorizedWhenInUse else {
      finish()
      return
    }
    guard !requestIssued else { return }
    guard !preferences.bool(forKey: Self.upgradePromptKey) else {
      finish()
      return
    }
    guard let description = Bundle.main.object(
      forInfoDictionaryKey: "NSLocationAlwaysAndWhenInUseUsageDescription"
    ) as? String, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      finish()
      return
    }
    requestIssued = true
    manager.requestAlwaysAuthorization()
    guard !results.isEmpty, !promptObserved else { return }
    let check = DispatchWorkItem { [weak self] in
      guard let self = self, self.applicationState() == .active,
            !self.promptObserved else { return }
      self.finish()
    }
    noPromptCheck = check
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.noPromptDelay, execute: check)
  }

  @objc private func willResignActive(_ notification: Notification) {
    guard requestIssued, !results.isEmpty else { return }
    promptObserved = true
    preferences.set(true, forKey: Self.upgradePromptKey)
    noPromptCheck?.cancel()
    noPromptCheck = nil
  }

  @objc private func didBecomeActive(_ notification: Notification) {
    guard !results.isEmpty else { return }
    if requestIssued {
      finish()
    } else {
      advanceRequest()
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if manager.authorizationStatus == .notDetermined {
      preferences.removeObject(forKey: Self.upgradePromptKey)
    }
    guard !results.isEmpty, applicationState() == .active,
          manager.authorizationStatus != .authorizedWhenInUse else { return }
    finish()
  }

  private func finish() {
    noPromptCheck?.cancel()
    noPromptCheck = nil
    let pending = results
    results.removeAll()
    requestIssued = false
    promptObserved = false
    let allowed = manager.authorizationStatus == .authorizedAlways
    for result in pending { result(allowed) }
  }
}
