import Foundation

public actor RigCtlCommandProcessor {
    private let radio: any RadioControlling

    public init(radio: any RadioControlling) {
        self.radio = radio
    }

    public func handle(_ rawCommand: String) async -> String {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = await radio.snapshot()

        if command == "f" {
            return "\(snapshot.frequencyHz)\n"
        }
        if command == "m" {
            return "\(Self.rigCtlMode(snapshot.mode))\n0\n"
        }
        if command == "t" {
            return "\(snapshot.isTransmitting ? 1 : 0)\n"
        }
        if command == "\\get_info" {
            return "OM0RX-xCat\n"
        }
        if command.hasPrefix("F ") {
            guard let frequency = Int64(command.dropFirst(2)), frequency > 0 else {
                return "RPRT -1\n"
            }
            do {
                try await radio.setFrequency(frequency)
                return "RPRT 0\n"
            } catch {
                return "RPRT -1\n"
            }
        }
        if command.hasPrefix("M ") {
            let fields = command.split(separator: " ")
            guard fields.count >= 2 else { return "RPRT -1\n" }
            do {
                try await radio.setMode(String(fields[1]))
                return "RPRT 0\n"
            } catch {
                return "RPRT -1\n"
            }
        }
        if command.hasPrefix("T ") {
            let enabled = command.dropFirst(2) == "1"
            do {
                try await radio.setTransmit(enabled)
                return "RPRT 0\n"
            } catch {
                return "RPRT -1\n"
            }
        }
        return "RPRT -4\n"
    }

    private static func rigCtlMode(_ mode: String) -> String {
        switch mode.uppercased() {
        case "DIGU": "PKTUSB"
        case "DIGL": "PKTLSB"
        case "NFM", "DFM": "FM"
        default: mode.uppercased()
        }
    }
}
