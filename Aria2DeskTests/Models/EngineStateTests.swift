import Testing
@testable import Aria2Desk

@Suite struct EngineStateTests {
    @Test(arguments: [
        EngineState.stopped, .starting, .running, .error("test"),
    ]) func engineStateLabelNonEmpty(state: EngineState) {
        #expect(!state.label.isEmpty)
    }

    @Test func errorStateLabel() {
        #expect(EngineState.error("x").label == "Error")
    }

    @Test func runningStateLabel() {
        #expect(EngineState.running.label == "Running")
    }
}
