import ActivityKit
import Flutter

enum DriverMissionActivityBridge {
  private static let channelName = "com.denkma.app/driver_mission_activity"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard #available(iOS 16.1, *) else {
        result(nil)
        return
      }

      switch call.method {
      case "start":
        guard let arguments = call.arguments as? [String: Any],
              let missionId = arguments["missionId"] as? String,
              let deadlineString = arguments["deadline"] as? String,
              let deadline = ISO8601DateFormatter().date(from: deadlineString) else {
          result(FlutterError(code: "invalid_arguments", message: "Mission ou délai invalide", details: nil))
          return
        }
        Task {
          do {
            let attributes = DenkmaMissionAttributes(
              missionId: missionId,
              trackingCode: arguments["trackingCode"] as? String ?? ""
            )
            if Activity<DenkmaMissionAttributes>.activities.contains(where: {
              $0.attributes.missionId == missionId
            }) {
              result(nil)
              return
            }
            for activity in Activity<DenkmaMissionAttributes>.activities {
              await activity.end(nil, dismissalPolicy: .immediate)
            }
            let state = DenkmaMissionAttributes.ContentState(deadline: deadline)
            _ = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
            result(nil)
          } catch {
            result(FlutterError(code: "activity_start_failed", message: error.localizedDescription, details: nil))
          }
        }
      case "end":
        Task {
          for activity in Activity<DenkmaMissionAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
          }
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

@available(iOS 16.1, *)
struct DenkmaMissionAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var deadline: Date
  }

  var missionId: String
  var trackingCode: String
}
