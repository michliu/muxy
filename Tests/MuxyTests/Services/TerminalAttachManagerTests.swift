import Foundation
import Testing

@testable import Muxy

@Suite("TerminalAttachManager")
@MainActor
struct TerminalAttachManagerTests {
    private func freshManager() -> TerminalAttachManager {
        TerminalAttachManager.shared
    }

    @Test("attach creates a buffer and records the client")
    func attachCreatesBuffer() {
        let manager = freshManager()
        let paneID = UUID()
        let clientID = UUID()

        manager.attach(paneID: paneID, clientID: clientID)

        #expect(manager.isAttached(clientID: clientID, paneID: paneID))
        #expect(manager.hasAnyAttachment(paneID: paneID))
        #expect(manager.buffer(for: paneID) != nil)

        manager.detachAll(clientID: clientID)
    }

    @Test("a second client reuses the same buffer")
    func secondClientReusesBuffer() {
        let manager = freshManager()
        let paneID = UUID()
        let first = UUID()
        let second = UUID()

        manager.attach(paneID: paneID, clientID: first)
        let buffer = manager.buffer(for: paneID)
        manager.attach(paneID: paneID, clientID: second)

        #expect(manager.buffer(for: paneID) === buffer)
        #expect(manager.attachedClients(for: paneID) == [first, second])

        manager.detachAll(clientID: first)
        manager.detachAll(clientID: second)
    }

    @Test("buffer is freed only when the last client detaches")
    func bufferFreedOnLastDetach() {
        let manager = freshManager()
        let paneID = UUID()
        let first = UUID()
        let second = UUID()

        manager.attach(paneID: paneID, clientID: first)
        manager.attach(paneID: paneID, clientID: second)

        manager.detach(paneID: paneID, clientID: first)
        #expect(manager.buffer(for: paneID) != nil)

        manager.detach(paneID: paneID, clientID: second)
        #expect(manager.buffer(for: paneID) == nil)
        #expect(!manager.hasAnyAttachment(paneID: paneID))
    }

    @Test("appendIfBuffered returns nil without an attachment and offsets when attached")
    func appendOffsets() {
        let manager = freshManager()
        let paneID = UUID()
        let clientID = UUID()

        #expect(manager.appendIfBuffered(paneID: paneID, bytes: Data("x".utf8)) == nil)

        manager.attach(paneID: paneID, clientID: clientID)
        #expect(manager.appendIfBuffered(paneID: paneID, bytes: Data("abc".utf8)) == 0)
        #expect(manager.appendIfBuffered(paneID: paneID, bytes: Data("de".utf8)) == 3)

        manager.detachAll(clientID: clientID)
    }

    @Test("detachAll removes the client from every pane and frees orphaned buffers")
    func detachAllClearsClient() {
        let manager = freshManager()
        let paneA = UUID()
        let paneB = UUID()
        let clientID = UUID()

        manager.attach(paneID: paneA, clientID: clientID)
        manager.attach(paneID: paneB, clientID: clientID)

        manager.detachAll(clientID: clientID)

        #expect(!manager.isAttached(clientID: clientID, paneID: paneA))
        #expect(!manager.isAttached(clientID: clientID, paneID: paneB))
        #expect(manager.buffer(for: paneA) == nil)
        #expect(manager.buffer(for: paneB) == nil)
    }
}
