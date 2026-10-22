import Foundation
import Testing
@testable import battery

/// A clock the tests move by hand.
@MainActor
private final class ManualClock {
    var now = Date(timeIntervalSinceReferenceDate: 1_000)

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

@MainActor
@Suite("Panel presentation")
struct PanelPresentationTests {
    private let clock = ManualClock()

    private func makePresentation() -> PanelPresentation {
        PanelPresentation { [clock] in clock.now }
    }

    @Test func opensWhenItWasNeverClosed() {
        #expect(makePresentation().shouldOpen())
    }

    @Test func ignoresTheClickThatClosedTheTransientPopover() {
        let presentation = makePresentation()
        presentation.didOpen()
        presentation.didClose()
        clock.advance(by: 0.1)
        #expect(!presentation.shouldOpen())
    }

    @Test func opensAgainOnceTheGuardHasPassed() {
        let presentation = makePresentation()
        presentation.didClose()
        clock.advance(by: PanelPresentation.reopenGuard + 0.01)
        #expect(presentation.shouldOpen())
    }

    @Test func tracksWhetherThePanelIsOpen() {
        let presentation = makePresentation()
        #expect(!presentation.isOpen)
        presentation.didOpen()
        #expect(presentation.isOpen)
        presentation.didClose()
        #expect(!presentation.isOpen)
    }

    @Test func closeAsksTheOwnerToClose() {
        let presentation = makePresentation()
        var closed = 0
        presentation.onClose = { closed += 1 }
        presentation.close()
        #expect(closed == 1)
    }

    @Test func openAboutClosesThePanelBeforeOpeningTheWindow() {
        let presentation = makePresentation()
        var calls: [String] = []
        presentation.onClose = { calls.append("close") }
        presentation.onOpenAbout = { calls.append("about") }
        presentation.openAbout()
        #expect(calls == ["close", "about"])
    }
}
