import SwiftUI

@main
struct LaneIOSPrototypeApp: App {
    @StateObject private var session = LaneSession()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(session) }
    }
}