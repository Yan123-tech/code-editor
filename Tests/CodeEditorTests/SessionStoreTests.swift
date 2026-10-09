import CodeEditorCore
import Foundation
import Testing

@Suite("SessionStore")
struct SessionStoreTests {
    /// A private defaults domain plus a cleanup closure, so the domain outlives
    /// the helper that made it.
    private func freshDefaults() -> (defaults: UserDefaults, cleanup: () -> Void) {
        let name = "SessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    @Test("a snapshot round-trips")
    func roundTrip() {
        let (defaults, cleanup) = freshDefaults()
        defer { cleanup() }

        let snapshot = SessionSnapshot(
            rootPath: "/tmp/project",
            openPaths: ["/tmp/project/a.swift", "/tmp/project/b.swift"],
            activePath: "/tmp/project/a.swift"
        )

        SessionStore.save(snapshot, defaults: defaults)
        #expect(SessionStore.load(defaults: defaults) == snapshot)
    }

    @Test("nothing saved loads as nil")
    func emptyLoadsNil() {
        let (defaults, cleanup) = freshDefaults()
        defer { cleanup() }
        #expect(SessionStore.load(defaults: defaults) == nil)
    }

    @Test("corrupt data loads as nil rather than crashing")
    func corruptDataLoadsNil() {
        let (defaults, cleanup) = freshDefaults()
        defer { cleanup() }
        defaults.set(Data("not json".utf8), forKey: "CodeEditor.session")

        #expect(SessionStore.load(defaults: defaults) == nil)
    }

    @Test("clear removes the snapshot")
    func clearRemoves() {
        let (defaults, cleanup) = freshDefaults()
        defer { cleanup() }
        SessionStore.save(SessionSnapshot(rootPath: "/tmp/x"), defaults: defaults)

        SessionStore.clear(defaults: defaults)
        #expect(SessionStore.load(defaults: defaults) == nil)
    }
}
