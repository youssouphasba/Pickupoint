import ActivityKit
import Flutter
import UIKit

enum DriverMissionActivityBridge {
  private static let channelName = "com.denkma.app/driver_mission_activity"

  private static func date(_ value: Any?) -> Date? {
    guard let text = value as? String else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
  }

  @available(iOS 16.1, *)
  private static func end(_ activity: Activity<DenkmaMissionAttributes>) async {
    if #available(iOS 16.2, *) {
      await activity.end(nil, dismissalPolicy: .immediate)
    } else {
      await activity.end(using: nil, dismissalPolicy: .immediate)
    }
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "start" || call.method == "end" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard #available(iOS 16.1, *) else {
        result(["status": "unsupported"])
        return
      }
      if call.method == "end" {
        Task { @MainActor in
          for activity in Activity<DenkmaMissionAttributes>.activities {
            await end(activity)
          }
          result(["status": "ended"])
        }
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let missionId = arguments["missionId"] as? String, !missionId.isEmpty,
            let assignedAt = date(arguments["assignedAt"]),
            let phase = arguments["phase"] as? String,
            phase == "pickup" || phase == "delivery" else {
        result(FlutterError(code: "invalid_arguments", message: "Mission invalide", details: nil))
        return
      }
      let deadline = phase == "pickup" ? date(arguments["deadline"]) : nil
      if phase == "pickup", let value = arguments["deadline"], !(value is NSNull), deadline == nil {
        result(FlutterError(code: "invalid_arguments", message: "Délai de collecte invalide", details: nil))
        return
      }
      Task { @MainActor in
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
          result(["status": "disabled"])
          return
        }
        let state = DenkmaMissionAttributes.ContentState(
          phase: phase, assignedAt: assignedAt, deadline: deadline
        )
        let activities = Activity<DenkmaMissionAttributes>.activities
        let existing = activities.first {
          $0.attributes.missionId == missionId &&
            ($0.activityState == .active || $0.activityState == .stale)
        }
        for activity in activities where activity.id != existing?.id {
          await end(activity)
        }
        if let activity = existing {
          if #available(iOS 16.2, *) {
            await activity.update(ActivityContent(state: state, staleDate: deadline))
          } else {
            await activity.update(using: state)
          }
          result(["status": "active", "activityId": activity.id])
          return
        }
        guard UIApplication.shared.applicationState == .active else {
          result(["status": "deferred"])
          return
        }
        do {
          let attributes = DenkmaMissionAttributes(
            missionId: missionId,
            trackingCode: arguments["trackingCode"] as? String ?? ""
          )
          let activity: Activity<DenkmaMissionAttributes>
          if #available(iOS 16.2, *) {
            activity = try Activity.request(
              attributes: attributes,
              content: ActivityContent(state: state, staleDate: deadline),
              pushType: nil
            )
          } else {
            activity = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
          }
          result(["status": "active", "activityId": activity.id])
        } catch {
          result(FlutterError(code: "activity_start_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}

@available(iOS 16.1, *)
struct DenkmaMissionAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var phase: String?
    var assignedAt: Date?
    var deadline: Date?

    var isPickup: Bool { phase != "delivery" }
  }

  var missionId: String
  var trackingCode: String
}
