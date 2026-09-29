import SwiftUI

@main
struct DomainWidgetApp: App {
    var body: some Scene {
        #if os(macOS)
        MenuBarExtra("Datos de dominio", systemImage: "globe.desk") {
            ContentView()
                .frame(width: 420, height: 580)
        }
        .menuBarExtraStyle(.window)

        Window("Datos de dominio", id: "main") {
            ContentView()
                .frame(minWidth: 420, minHeight: 560)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 440, height: 640)
        #else
        WindowGroup {
            ContentView()
        }
        #endif
    }
}
