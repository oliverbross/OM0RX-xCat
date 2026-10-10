import Foundation

public actor CATCommandProcessor {
    private let radio: any RadioControlling
    private let allowTransmit: Bool
    private var autoInformation = 0
    private var receiveVFO = 0
    private var transmitVFO = 0

    public init(radio: any RadioControlling, allowTransmit: Bool = false) {
        self.radio = radio
        self.allowTransmit = allowTransmit
    }

    public func handle(_ rawCommand: String) async -> String? {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return nil }

        let snapshot = await radio.snapshot()
        switch command.uppercased() {
        case "ID":
            return "ID019;"
        case "PS":
            return "PS1;"
        case "AI": return "AI\(autoInformation);"
        case "FA":
            return Self.frequencyResponse(prefix: "FA", hertz: snapshot.frequencyHz)
        case "FB":
            guard let frequency = await radio.secondaryFrequency() else { return "?;" }
            return Self.frequencyResponse(prefix: "FB", hertz: frequency)
        case "FR": return "FR\(receiveVFO);"
        case "FT": return "FT\(transmitVFO);"
        case "KS": return String(format: "KS%03d;", await radio.cwSpeed())
        case "IF": return Self.informationResponse(snapshot: snapshot, transmitVFO: transmitVFO)
        case "MD":
            return "MD\(Self.kenwoodMode(for: snapshot.mode));"
        case "TX", "TX0", "TX1", "TX2":
            guard allowTransmit else { return "?;" }
            do {
                let mode: CATTransmitMode = command.uppercased() == "TX2" ? .tune : (command.uppercased() == "TX1" ? .data : .microphone)
                try await radio.setTransmit(mode)
                return nil
            } catch {
                return "?;"
            }
        case "RX":
            do {
                try await radio.setTransmit(false)
                return nil
            } catch {
                return "?;"
            }
        default:
            if command.uppercased().hasPrefix("AI"), command.count == 3,
               let value = Int(command.dropFirst(2)), (0...2).contains(value) {
                autoInformation = value
                return nil
            }
            if command.uppercased().hasPrefix("FA"), command.count > 2 {
                return await setFrequency(String(command.dropFirst(2)))
            }
            if command.uppercased().hasPrefix("FB"), command.count > 2 {
                return await setSecondaryFrequency(String(command.dropFirst(2)))
            }
            if command.uppercased().hasPrefix("MD"), command.count > 2 {
                return await setMode(String(command.dropFirst(2)))
            }
            if command.uppercased().hasPrefix("KS"), command.count > 2 {
                return await setCWSpeed(String(command.dropFirst(2)))
            }
            if command.uppercased().hasPrefix("FR"), command.count == 3 {
                return await setReceiveVFO(String(command.dropFirst(2)))
            }
            if command.uppercased().hasPrefix("FT"), command.count == 3 {
                return await setTransmitVFO(String(command.dropFirst(2)))
            }
            if command.uppercased().hasPrefix("KY") {
                return await handleCW(String(command.dropFirst(2)))
            }
            return "?;"
        }
    }

    private func setSecondaryFrequency(_ value: String) async -> String? {
        guard value.count == 11, let frequency = Int64(value), frequency > 0 else { return "?;" }
        do { try await radio.setSecondaryFrequency(frequency); return nil } catch { return "?;" }
    }

    private func setCWSpeed(_ value: String) async -> String? {
        guard value.count == 3, let speed = Int(value), (5...100).contains(speed) else { return "?;" }
        do { try await radio.setCWSpeed(speed); return nil } catch { return "?;" }
    }

    private func setReceiveVFO(_ value: String) async -> String? {
        guard let vfo = Int(value), vfo == 0 || vfo == 1 else { return "?;" }
        do { try await radio.setReceiveVFO(vfo); receiveVFO = vfo; return nil } catch { return "?;" }
    }

    private func setTransmitVFO(_ value: String) async -> String? {
        guard let vfo = Int(value), vfo == 0 || vfo == 1 else { return "?;" }
        do { try await radio.setSplitTransmit(vfo == 1); transmitVFO = vfo; return nil } catch { return "?;" }
    }

    private func handleCW(_ value: String) async -> String? {
        if value.isEmpty { return "KY0;" }
        guard allowTransmit else { return "?;" }
        if value.trimmingCharacters(in: .whitespaces).isEmpty {
            do { try await radio.clearCW(); return nil } catch { return "?;" }
        }
        guard value.count <= 128 else { return "?;" }
        do { try await radio.sendCW(value.trimmingCharacters(in: .whitespaces)); return nil } catch { return "?;" }
    }

    private func setFrequency(_ value: String) async -> String? {
        guard let frequency = Int64(value), frequency > 0 else { return "?;" }
        do {
            try await radio.setFrequency(frequency)
            return nil
        } catch {
            return "?;"
        }
    }

    private func setMode(_ value: String) async -> String? {
        guard let mode = Self.flexMode(forKenwoodCode: value) else { return "?;" }
        do {
            try await radio.setMode(mode)
            return nil
        } catch {
            return "?;"
        }
    }

    private static func frequencyResponse(prefix: String, hertz: Int64) -> String {
        String(format: "%@%011lld;", prefix, hertz)
    }

    private static func kenwoodMode(for mode: String) -> Int {
        switch mode.uppercased() {
        case "LSB": 1
        case "USB": 2
        case "CW": 3
        case "FM", "NFM", "DFM", "PKTFM": 4
        case "AM", "SAM": 5
        case "DIGL", "PKTLSB", "RTTY", "RTTYR": 6
        case "CWR": 7
        case "DIGU", "PKTUSB": 9
        default: 2
        }
    }

    private static func flexMode(forKenwoodCode code: String) -> String? {
        switch code {
        case "1": "LSB"
        case "2": "USB"
        case "3": "CW"
        case "4": "FM"
        case "5": "AM"
        case "6": "RTTY"
        case "7": "CWR"
        case "9": "DIGU"
        default: nil
        }
    }

    private static func informationResponse(snapshot: RadioSnapshot, transmitVFO: Int) -> String {
        let frequency = String(format: "%011lld", snapshot.frequencyHz)
        let mode = kenwoodMode(for: snapshot.mode)
        let tx = snapshot.isTransmitting ? 1 : 0
        return "IF\(frequency)     +000000000\(tx)\(mode)000000\(transmitVFO)0;"
    }
}
