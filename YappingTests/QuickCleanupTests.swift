import Testing
@testable import Yapping

struct QuickCleanupTests {
    private func clean(_ s: String) -> String { QuickCleanupProcessor.clean(s) }

    @Test func removesVocalFillers() {
        #expect(clean("So um, send the report tomorrow.") == "So send the report tomorrow.")
        #expect(clean("Uh, I think we should go.") == "I think we should go.")
        #expect(clean("It's, you know, fine.") == "It's fine.")
        #expect(clean("Send it, um, today.") == "Send it today.")
    }

    @Test func collapsesStutters() {
        #expect(clean("I think the the deadline moved.") == "I think the deadline moved.")
        #expect(clean("I I I want that.") == "I want that.")
    }

    @Test func leavesCleanTextAlone() {
        #expect(clean("Hello, yep. I was mute. Sorry, bro.") == "Hello, yep. I was mute. Sorry, bro.")
        #expect(clean("The umbrella is under the umpire's chair.") == "The umbrella is under the umpire's chair.")
    }

    @Test func fixesCapitalizationAndTerminalPunctuation() {
        #expect(clean("send the report") == "Send the report.")
        #expect(clean("done. next item") == "Done. Next item.")
        #expect(clean("really?") == "Really?")
    }

    @Test func emptyStaysEmpty() {
        #expect(clean("   ") == "")
    }
}
