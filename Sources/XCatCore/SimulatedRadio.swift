import Foundation

public actor SimulatedRadio: RadioControlling {
    private var value: RadioSnapshot
    private var vfoBFrequencyHz: Int64?
    private var speed = 25
    private var cwText = ""

    public init(snapshot: RadioSnapshot = RadioSnapshot()) {
        value = snapshot
    }

    public func snapshot() -> RadioSnapshot {
        value
    }

    public func setFrequency(_ frequencyHz: Int64) throws {
        guard frequencyHz > 0 else { throw XCatError.invalidFrequency }
        value.frequencyHz = frequencyHz
    }

    public func setMode(_ mode: String) throws {
        let normalized = mode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { throw XCatError.invalidMode }
        value.mode = normalized
    }

    public func setTransmit(_ enabled: Bool) {
        value.isTransmitting = enabled
    }

    public func secondaryFrequency() -> Int64? { vfoBFrequencyHz }

    public func setSecondaryFrequency(_ frequencyHz: Int64) throws {
        guard frequencyHz > 0 else { throw XCatError.invalidFrequency }
        vfoBFrequencyHz = frequencyHz
    }

    public func setSplitTransmit(_ enabled: Bool) {
        if enabled, vfoBFrequencyHz == nil { vfoBFrequencyHz = value.frequencyHz }
        if !enabled { vfoBFrequencyHz = nil }
    }

    public func setReceiveVFO(_ vfo: Int) throws {
        guard vfo == 0 || (vfo == 1 && vfoBFrequencyHz != nil) else { throw XCatError.unsupported }
    }

    public func cwSpeed() -> Int { speed }

    public func setCWSpeed(_ wordsPerMinute: Int) throws {
        guard (5...100).contains(wordsPerMinute) else { throw XCatError.server("CW speed must be 5 through 100 WPM.") }
        speed = wordsPerMinute
    }

    public func sendCW(_ text: String) { cwText = text }
    public func clearCW() { cwText = "" }
    public func setTransmit(_ mode: CATTransmitMode) { value.isTransmitting = true }
}
