import Foundation
import Testing
import APIMeterCore

struct AlertStateMachineTests {

    @Test func notifiesOncePerDrop() {
        var machine = AlertStateMachine()
        // 9.80 < 10 -> alert
        #expect(machine.evaluate(balance: Decimal(string: "9.80")!, threshold: 10) == true)
        // keeps dropping -> silent
        #expect(machine.evaluate(balance: Decimal(string: "9.60")!, threshold: 10) == false)
        #expect(machine.evaluate(balance: Decimal(string: "8.80")!, threshold: 10) == false)
    }

    @Test func rearmsAfterRisingAboveThreshold() {
        var machine = AlertStateMachine()
        #expect(machine.evaluate(balance: Decimal(string: "9.00")!, threshold: 10) == true)
        // user tops up
        #expect(machine.evaluate(balance: Decimal(string: "30.00")!, threshold: 10) == false)
        // drops again -> notify again
        #expect(machine.evaluate(balance: Decimal(string: "9.50")!, threshold: 10) == true)
    }

    @Test func noAlertWhenAboveThreshold() {
        var machine = AlertStateMachine()
        #expect(machine.evaluate(balance: Decimal(string: "25.00")!, threshold: 10) == false)
        #expect(machine.alerted == false)
    }
}
