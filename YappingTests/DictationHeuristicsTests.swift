import Testing
@testable import Yapping

struct DictationHeuristicsTests {
    @Test func cleanSentenceSkipsModel() {
        #expect(!DictationHeuristics.needsCleanup("Hello, yep. I was mute. Sorry, bro."))
        #expect(!DictationHeuristics.needsCleanup("Send the report tomorrow morning and copy Ana."))
    }

    @Test func fillersTriggerModel() {
        #expect(DictationHeuristics.needsCleanup("So um, send the report tomorrow."))
        #expect(DictationHeuristics.needsCleanup("Uh, I think we should go."))
        #expect(DictationHeuristics.needsCleanup("It's, you know, fine."))
    }

    @Test func correctionsTriggerModel() {
        #expect(DictationHeuristics.needsCleanup("Meet on Tuesday, no wait, Wednesday."))
        #expect(DictationHeuristics.needsCleanup("Book it for two, I mean three people."))
    }

    @Test func stutterTriggersModel() {
        #expect(DictationHeuristics.needsCleanup("I think the the deadline moved."))
    }

    @Test func wordsContainingFillerAreNotFillers() {
        #expect(!DictationHeuristics.needsCleanup("The umbrella is under the umpire's chair."))
        #expect(!DictationHeuristics.needsCleanup("Hummus and summer."))
    }
}
