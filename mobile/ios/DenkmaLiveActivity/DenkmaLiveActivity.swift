import ActivityKit
import SwiftUI
import WidgetKit

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

@available(iOS 16.1, *)
private struct MissionTimer: View {
  let state: DenkmaMissionAttributes.ContentState

  var body: some View {
    Group {
      if state.isPickup, let deadline = state.deadline {
        Text(timerInterval: min(state.assignedAt ?? Date.now, deadline)...deadline, countsDown: true)
      } else if let assignedAt = state.assignedAt {
        Text(assignedAt, style: .timer)
      } else {
        Text("—")
      }
    }
    .monospacedDigit()
    .lineLimit(1)
    .minimumScaleFactor(0.7)
  }
}

@available(iOS 16.1, *)
struct DenkmaLiveActivity: Widget {
  private func title(_ state: DenkmaMissionAttributes.ContentState) -> String {
    state.isPickup ? "Collecte à confirmer" : "Livraison en cours"
  }

  private func missionURL(_ missionId: String) -> URL? {
    var components = URLComponents()
    components.scheme = "denkma"
    components.host = "app"
    components.path = "/driver/mission/\(missionId)"
    return components.url
  }

  var body: some WidgetConfiguration {
    ActivityConfiguration(for: DenkmaMissionAttributes.self) { context in
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Image(systemName: "shippingbox.fill")
            .foregroundStyle(.orange)
          Text("Denkma · \(title(context.state))")
            .font(.headline)
            .lineLimit(2)
        }
        MissionTimer(state: context.state)
          .font(.system(size: 30, weight: .bold, design: .rounded))
          .foregroundStyle(context.state.isPickup ? Color.orange : Color.green)
        HStack {
          if !context.attributes.trackingCode.isEmpty {
            Text(context.attributes.trackingCode)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
          Spacer(minLength: 8)
          Text(context.state.isPickup && context.state.deadline != nil
               ? "Temps restant" : "Depuis l’acceptation")
        }
        .font(.caption)
        .foregroundStyle(Color.black.opacity(0.65))
      }
      .padding()
      .foregroundStyle(Color.black)
      .activityBackgroundTint(Color.white)
      .activitySystemActionForegroundColor(Color.black)
      .widgetURL(missionURL(context.attributes.missionId))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: "shippingbox.fill")
            .foregroundStyle(.orange)
        }
        DynamicIslandExpandedRegion(.center) {
          MissionTimer(state: context.state)
            .font(.headline)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(title(context.state))
            .font(.caption)
        }
      } compactLeading: {
        Image(systemName: "shippingbox.fill")
      } compactTrailing: {
        MissionTimer(state: context.state)
          .frame(maxWidth: 64)
      } minimal: {
        Image(systemName: "timer")
      }
      .widgetURL(missionURL(context.attributes.missionId))
    }
  }
}

@main
struct DenkmaLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    DenkmaLiveActivity()
  }
}
