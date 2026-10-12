import Foundation
import Testing
@testable import CodeEditorCore

@Suite("RecentProjectsStore")
struct RecentProjectsStoreTests {
    private func makeIsolatedDefaults() -> UserDefaults {
        let name = "test.recentProjects.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("empty defaults returns empty list")
    func emptyDefaults() {
        let defaults = makeIsolatedDefaults()
        let recents = RecentProjectsStore.load(defaults: defaults)
        #expect(recents.isEmpty)
    }

    @Test("records projects in MRU order")
    func recordsMRU() {
        let defaults = makeIsolatedDefaults()
        let tmp = FileManager.default.temporaryDirectory
        let folderA = tmp.appendingPathComponent("ProjectA")
        let folderB = tmp.appendingPathComponent("ProjectB")
        try? FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folderA)
            try? FileManager.default.removeItem(at: folderB)
        }

        RecentProjectsStore.record(url: folderA, defaults: defaults)
        RecentProjectsStore.record(url: folderB, defaults: defaults)

        var loaded = RecentProjectsStore.load(defaults: defaults)
        #expect(loaded.count == 2)
        #expect(loaded.first?.name == "ProjectB")

        // Re-recording A moves it to the top
        RecentProjectsStore.record(url: folderA, defaults: defaults)
        loaded = RecentProjectsStore.load(defaults: defaults)
        #expect(loaded.count == 2)
        #expect(loaded.first?.name == "ProjectA")
    }

    @Test("removes project from recents")
    func removeProject() {
        let defaults = makeIsolatedDefaults()
        let tmp = FileManager.default.temporaryDirectory
        let folder = tmp.appendingPathComponent("ProjectToRemove")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }

        RecentProjectsStore.record(url: folder, defaults: defaults)
        #expect(RecentProjectsStore.load(defaults: defaults).count == 1)

        RecentProjectsStore.remove(url: folder, defaults: defaults)
        #expect(RecentProjectsStore.load(defaults: defaults).isEmpty)
    }
}
