import SwiftUI
import AppKit
import Sparkle

@main
struct DettoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var settings = AppSettings()
    @State private var dictationController = DictationController()
    @State private var menuBarAnimator: MenuBarAnimator?
    private let updaterController = AppUpdaterController()

    init() {
        DettoTheme.registerFonts()
        TranscriptionEngine.cleanupOrphanedAudioFiles()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(settings: settings, dictationController: dictationController)
                .id(settings.darkMode)
                .onAppear {
                    settings.applyScreenShareVisibility()
                }
                .onChange(of: settings.darkMode) {
                    for window in NSApp.windows where window.level == .normal {
                        window.backgroundColor = NSColor(Color.dBg)
                    }
                }
        }
        .defaultSize(width: 340, height: 580)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
        Settings {
            SettingsView(settings: settings, updater: updaterController.updater, dictationController: dictationController)
        }
        MenuBarExtra {
            DictationMenuContent(controller: dictationController)
                .onAppear {
                    if menuBarAnimator == nil {
                        let animator = MenuBarAnimator(state: dictationController.state)
                        animator.start()
                        menuBarAnimator = animator
                    }
                }
        } label: {
            if let animator = menuBarAnimator {
                MenuBarLabel(state: dictationController.state, animator: animator)
            } else {
                Text("D")
                    .font(.custom("Azeret Mono", size: 14).weight(.black))
            }
        }
    }
}

/// Observes new window creation and applies screen-share visibility setting.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        for window in NSApp.windows {
            applyWindowChrome(window)
        }

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                for window in NSApp.windows {
                    self.applyWindowChrome(window)
                }
            }
        }
    }

    private func applyWindowChrome(_ window: NSWindow) {
        guard window.level == .normal else { return }

        window.titlebarAppearsTransparent = true
        let dark = UserDefaults.standard.bool(forKey: "darkMode")
        window.backgroundColor = dark
            ? NSColor(red: 0.098, green: 0.098, blue: 0.098, alpha: 1)
            : NSColor(red: 0.992, green: 0.984, blue: 0.969, alpha: 1)
        window.titleVisibility = .hidden

        let hidden = UserDefaults.standard.object(forKey: "hideFromScreenShare") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "hideFromScreenShare")
        window.sharingType = hidden ? .none : .readOnly
    }
}
