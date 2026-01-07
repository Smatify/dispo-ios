import ActivityKit
import WidgetKit
import SwiftUI

struct ShiftStatusAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var isActive: Bool
        var updateCount: Int
        var lastUpdate: String
    }
    
    var name: String
}

@available(iOS 16.1, *)
struct ShiftStatusWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShiftStatusWidget()
    }
}

@available(iOS 16.1, *)
struct ShiftStatusWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShiftStatusAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: context.state.isActive ? "location.fill" : "location.slash")
                        .foregroundColor(context.state.isActive ? .green : .gray)
                    Text("Fahrdienst Dispatch")
                        .font(.headline)
                }
                
                if context.state.isActive {
                    Text("Shift Active")
                        .font(.subheadline)
                        .foregroundColor(.green)
                    Text("Updates: \(context.state.updateCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Last: \(context.state.lastUpdate)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Shift Inactive")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.1))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isActive ? "location.fill" : "location.slash")
                        .foregroundColor(context.state.isActive ? .green : .gray)
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.updateCount)")
                        .font(.headline)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.isActive ? "Shift Active" : "Shift Inactive")
                            .font(.subheadline)
                        Text("Last update: \(context.state.lastUpdate)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isActive ? "location.fill" : "location.slash")
                    .foregroundColor(context.state.isActive ? .green : .gray)
            } compactTrailing: {
                Text("\(context.state.updateCount)")
                    .font(.caption2)
            } minimal: {
                Image(systemName: context.state.isActive ? "location.fill" : "location.slash")
                    .foregroundColor(context.state.isActive ? .green : .gray)
            }
        }
    }
}

