import AppKit
import Foundation
import Observation
import CoreAudio
import os

enum SessionType: String {
    case callCapture
    case voiceMemo
}

@Observable
@MainActor
final class AppSettings {
    private let log = Logger(subsystem: "io.gremble.detto", category: "AppSettings")

    var transcriptionLocale: String {
        didSet { UserDefaults.standard.set(transcriptionLocale, forKey: "transcriptionLocale") }
    }

    /// Stored as the AudioDeviceID integer. 0 means "use system default".
    var inputDeviceID: AudioDeviceID {
        didSet { UserDefaults.standard.set(Int(inputDeviceID), forKey: "inputDeviceID") }
    }

    var vaultMeetingsPath: String {
        didSet { UserDefaults.standard.set(vaultMeetingsPath, forKey: "vaultMeetingsPath") }
    }

    var vaultVoicePath: String {
        didSet { UserDefaults.standard.set(vaultVoicePath, forKey: "vaultVoicePath") }
    }

    var vaultRootPath: String {
        didSet { UserDefaults.standard.set(vaultRootPath, forKey: "vaultRootPath") }
    }

    // Security-scoped bookmarks for persistent folder access across reboots
    var vaultMeetingsBookmark: Data? {
        didSet { UserDefaults.standard.set(vaultMeetingsBookmark, forKey: "vaultMeetingsBookmark") }
    }

    var vaultVoiceBookmark: Data? {
        didSet { UserDefaults.standard.set(vaultVoiceBookmark, forKey: "vaultVoiceBookmark") }
    }

    var vaultRootBookmark: Data? {
        didSet { UserDefaults.standard.set(vaultRootBookmark, forKey: "vaultRootBookmark") }
    }

    var vocabularyPath: String {
        didSet { UserDefaults.standard.set(vocabularyPath, forKey: "vocabularyPath") }
    }

    var vocabularyBookmark: Data? {
        didSet { UserDefaults.standard.set(vocabularyBookmark, forKey: "vocabularyBookmark") }
    }

    var enabledVocabPacks: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabledVocabPacks), forKey: "enabledVocabPacks") }
    }

    var enablePostSessionRefinement: Bool {
        didSet { UserDefaults.standard.set(enablePostSessionRefinement, forKey: "enablePostSessionRefinement") }
    }

    var darkMode: Bool {
        didSet { UserDefaults.standard.set(darkMode, forKey: "darkMode") }
    }

    /// When true, all app windows are invisible to screen sharing / recording.
    var hideFromScreenShare: Bool {
        didSet {
            UserDefaults.standard.set(hideFromScreenShare, forKey: "hideFromScreenShare")
            applyScreenShareVisibility()
        }
    }

    /// Tracks resolved security-scoped URLs that need stopAccessingSecurityScopedResource on deinit.
    private nonisolated(unsafe) var accessedURLs: [URL] = []

    init() {
        let defaults = UserDefaults.standard
        self.transcriptionLocale = defaults.string(forKey: "transcriptionLocale") ?? "en-US"
        self.inputDeviceID = AudioDeviceID(defaults.integer(forKey: "inputDeviceID"))
        self.vaultMeetingsPath = defaults.string(forKey: "vaultMeetingsPath") ?? NSString("~/Documents/Detto/Meetings").expandingTildeInPath
        self.vaultVoicePath = defaults.string(forKey: "vaultVoicePath") ?? NSString("~/Documents/Detto/Voice").expandingTildeInPath
        self.vaultRootPath = defaults.string(forKey: "vaultRootPath") ?? ""
        self.vaultMeetingsBookmark = defaults.data(forKey: "vaultMeetingsBookmark")
        self.vaultVoiceBookmark = defaults.data(forKey: "vaultVoiceBookmark")
        self.vaultRootBookmark = defaults.data(forKey: "vaultRootBookmark")
        self.vocabularyPath = defaults.string(forKey: "vocabularyPath") ?? ""
        self.vocabularyBookmark = defaults.data(forKey: "vocabularyBookmark")
        if let savedPacks = defaults.array(forKey: "enabledVocabPacks") as? [String] {
            self.enabledVocabPacks = Set(savedPacks)
        } else {
            self.enabledVocabPacks = ["canadian-politics"]
        }
        self.enablePostSessionRefinement = defaults.object(forKey: "enablePostSessionRefinement") as? Bool ?? true
        self.darkMode = defaults.bool(forKey: "darkMode")
        // Default to true (hidden) if key has never been set
        if defaults.object(forKey: "hideFromScreenShare") == nil {
            self.hideFromScreenShare = true
        } else {
            self.hideFromScreenShare = defaults.bool(forKey: "hideFromScreenShare")
        }

        resolveAllBookmarks()
    }

    /// Resolve all stored bookmarks to restore file access after reboot.
    private func resolveAllBookmarks() {
        if let bookmark = vaultMeetingsBookmark {
            if let result = resolveBookmark(bookmark) {
                vaultMeetingsPath = result.url.path
                if let refreshed = result.refreshedBookmark {
                    vaultMeetingsBookmark = refreshed
                }
            }
        }
        if let bookmark = vaultVoiceBookmark {
            if let result = resolveBookmark(bookmark) {
                vaultVoicePath = result.url.path
                if let refreshed = result.refreshedBookmark {
                    vaultVoiceBookmark = refreshed
                }
            }
        }
        if let bookmark = vaultRootBookmark {
            if let result = resolveBookmark(bookmark) {
                vaultRootPath = result.url.path
                if let refreshed = result.refreshedBookmark {
                    vaultRootBookmark = refreshed
                }
            }
        }
        if let bookmark = vocabularyBookmark {
            if let result = resolveBookmark(bookmark) {
                vocabularyPath = result.url.path
                if let refreshed = result.refreshedBookmark {
                    vocabularyBookmark = refreshed
                }
            }
        }
    }

    /// Resolve a security-scoped bookmark and start accessing the resource.
    private func resolveBookmark(_ bookmarkData: Data) -> (url: URL, refreshedBookmark: Data?)? {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if url.startAccessingSecurityScopedResource() {
                accessedURLs.append(url)
            }
            var refreshed: Data?
            if isStale {
                log.warning("Bookmark is stale for \(url.path), re-creating")
                refreshed = createBookmark(for: url)
            }
            return (url: url, refreshedBookmark: refreshed)
        } catch {
            log.error("Failed to resolve bookmark: \(error.localizedDescription)")
            return nil
        }
    }

    /// Create a security-scoped bookmark for a URL.
    func createBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            log.error("Failed to create bookmark for \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    /// Apply current screen-share visibility to all app windows.
    func applyScreenShareVisibility() {
        let type: NSWindow.SharingType = hideFromScreenShare ? .none : .readOnly
        for window in NSApp.windows {
            window.sharingType = type
        }
    }

    var vaultMeetingsURL: URL? {
        guard !vaultMeetingsPath.isEmpty else { return nil }
        return URL(fileURLWithPath: vaultMeetingsPath)
    }

    var vaultVoiceURL: URL? {
        guard !vaultVoicePath.isEmpty else { return nil }
        return URL(fileURLWithPath: vaultVoicePath)
    }

    var vaultRootURL: URL? {
        guard !vaultRootPath.isEmpty else { return nil }
        return URL(fileURLWithPath: vaultRootPath)
    }

    var vocabularyURL: URL? {
        guard !vocabularyPath.isEmpty else { return nil }
        return URL(fileURLWithPath: vocabularyPath)
    }

    var locale: Locale {
        Locale(identifier: transcriptionLocale)
    }

    deinit {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
