import SwiftUI
import WidgetKit

@main
struct KaukoControlBundle: WidgetBundle {
    var body: some Widget {
        KaukoControl()
    }
}

struct KaukoControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.example.remote.control") {
            ControlWidgetButton(action: OpenKaukoIntent()) {
                Label("Kauko", systemImage: "av.remote")
            }
        }
        .displayName("Kauko")
        .description("Avaa Kauko")
    }
}
