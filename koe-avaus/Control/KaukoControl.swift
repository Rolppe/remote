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
        StaticControlConfiguration(kind: "remote.control") {
            ControlWidgetButton(action: OpenKaukoIntent()) {
                Label("Controller", systemImage: "av.remote")
            }
        }
        .displayName("Controller")
        .description("Avaa Controller")
    }
}
