import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct DenkmaMissionAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var deadline: Date
  }

  var missionId: String
  var trackingCode: String
}

@available(iOS 16.1, *)
struct DenkmaLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: DenkmaMissionAttributes.self) { context in
      VStack(alignment: .leading, spacing: 6) {
        Text("Temps pour récupérer le colis")
          .font(.headline)
        Text(context.state.deadline, style: .timer)
          .font(.system(size: 30, weight: .bold, design: .monospaced))
          .foregroundStyle(.orange)
        if !context.attributes.trackingCode.isEmpty {
          Text(context.attributes.trackingCode)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding()
      .activityBackgroundTint(Color.white)
      .activitySystemActionForegroundColor(Color.black)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: "shippingbox.fill")
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.state.deadline, style: .timer)
            .font(.headline.monospacedDigit())
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text("Temps pour récupérer le colis")
            .font(.caption)
        }
      } compactLeading: {
        Image(systemName: "shippingbox.fill")
      } compactTrailing: {
        Text(context.state.deadline, style: .timer)
          .monospacedDigit()
      } minimal: {
        Image(systemName: "timer")
      }
    }
  }
}

@main
struct DenkmaLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    DenkmaLiveActivity()
  }
}
