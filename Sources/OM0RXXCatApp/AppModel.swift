import Combine
import Foundation
import XCatCore

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration: AppConfiguration
    @Published private(set) var status = "Stopped"
    @Published private(set) var events: [String] = []
    @Published private(set) var isRunning = false

    private var catServer: TCPCommandServer?
    private var rigCtlServer: TCPCommandServer?
    private var radio: (any RadioControlling)?
    private var flexRadio: FlexRadioClient?

    init() {
        if let data = UserDefaults.standard.data(forKey: "configuration"),
           let stored = try? JSONDecoder().decode(AppConfiguration.self, from: data) {
            configuration = stored
        } else {
            configuration = AppConfiguration(
                connectionKind: .simulator,
                catPort: 15_002,
                rigCtlPort: 14_532
            )
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: "configuration")
        }
        record("Settings saved")
    }

    func start() {
        guard !isRunning else { return }
        do {
            let selectedRadio: any RadioControlling
            if configuration.connectionKind == .local {
                guard !configuration.radioHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw XCatError.server("Enter the local radio host or IP address.")
                }
                let client = FlexRadioClient(
                    host: configuration.radioHost,
                    port: configuration.radioPort,
                    stationName: configuration.stationName,
                    sliceLetter: configuration.sliceLetter,
                    onState: { [weak self] _, description in
                        Task { @MainActor in self?.status = description }
                    },
                    onSnapshot: { [weak self] snapshot in
                        Task { @MainActor in
                            self?.status = "\(snapshot.station) slice \(snapshot.slice): \(snapshot.frequencyHz) Hz \(snapshot.mode)"
                        }
                    }
                )
                flexRadio = client
                selectedRadio = client
            } else if configuration.connectionKind == .smartLink {
                throw XCatError.server("SmartLink needs an OM0RX-xCat FlexRadio OAuth client ID before it can be enabled.")
            } else {
                selectedRadio = SimulatedRadio(snapshot: RadioSnapshot(
                    frequencyHz: 14_074_000,
                    mode: "DIGU",
                    slice: configuration.sliceLetter,
                    station: configuration.stationName
                ))
            }
            radio = selectedRadio
            let catProcessor = CATCommandProcessor(radio: selectedRadio, allowTransmit: configuration.allowCATTransmit)
            let rigCtlProcessor = RigCtlCommandProcessor(radio: selectedRadio)

            let cat = TCPCommandServer(
                label: "com.oliverbross.OM0RXXCat.cat",
                framing: .semicolon,
                handler: { command in await catProcessor.handle(command) },
                onDisconnect: {
                    try? await selectedRadio.clearCW()
                    try? await selectedRadio.setTransmit(false)
                },
                onEvent: { [weak self] event in
                    Task { @MainActor in
                        self?.record("CAT: \(event)")
                        if event.contains("failed") { self?.status = event }
                    }
                }
            )
            let rigCtl = TCPCommandServer(
                label: "com.oliverbross.OM0RXXCat.rigctl",
                framing: .newline,
                handler: { command in await rigCtlProcessor.handle(command) },
                onEvent: { [weak self] event in
                    Task { @MainActor in
                        self?.record("RigCtlD: \(event)")
                        if event.contains("failed") { self?.status = event }
                    }
                }
            )
            try cat.start(port: configuration.catPort)
            try rigCtl.start(port: configuration.rigCtlPort)
            catServer = cat
            rigCtlServer = rigCtl
            isRunning = true
            status = configuration.connectionKind == .simulator ? "Simulator ready" : "Connecting to radio"
            record("OM0RX-xCat started")
            if let flexRadio {
                Task { await flexRadio.start() }
            }
        } catch {
            let message = error.localizedDescription
            stop()
            status = message
            record("Start failed: \(message)")
        }
    }

    func stop() {
        catServer?.stop()
        rigCtlServer?.stop()
        catServer = nil
        rigCtlServer = nil
        if let radio {
            Task {
                try? await radio.clearCW()
                try? await radio.setTransmit(false)
            }
        }
        if let flexRadio {
            Task { await flexRadio.stop() }
        }
        flexRadio = nil
        radio = nil
        isRunning = false
        status = "Stopped"
        record("OM0RX-xCat stopped")
    }

    private func record(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        events.append("\(formatter.string(from: Date()))  \(message)")
        if events.count > 200 {
            events.removeFirst(events.count - 200)
        }
    }
}
