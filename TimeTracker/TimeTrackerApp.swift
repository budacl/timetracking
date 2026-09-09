import AppKit
import SwiftUI
import UserNotifications

@main
struct TimeTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let store = AppStore.shared

    var body: some Scene {
        WindowGroup("Time Tracker", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 700, minHeight: 460)
                .handlesExternalEvents(preferring: ["review", "main"], allowing: ["*"])
                .onOpenURL { url in
                    if url.host == "review" { store.showReview = true }
                }
        }
        .defaultSize(width: 840, height: 580)
        .handlesExternalEvents(matching: ["*"])
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Keep running after the window is closed so the 16:00 review can still pop up.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        NSApp.activate(ignoringOtherApps: true)
        // Routed through the URL scheme so SwiftUI (re)opens the main window if it was closed.
        if let url = URL(string: "timetracker://review") {
            NSWorkspace.shared.open(url)
        }
    }
}
