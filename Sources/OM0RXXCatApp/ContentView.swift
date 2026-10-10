import AppKit
import SwiftUI
import XCatCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: WorkspaceTab = .status
    @State private var selectedSpotFeed: SpotFeed = .logbook

    private enum WorkspaceTab: Hashable {
        case status
        case activity
        case spots
        case station
        case configuration
    }

    private enum Layout {
        static let tight: CGFloat = 4
        static let compact: CGFloat = 8
        static let standard: CGFloat = 16
        static let generous: CGFloat = 20
        static let labelWidth: CGFloat = 154
        static let compactFieldWidth: CGFloat = 96
    }

    var body: some View {
        VStack(spacing: Layout.standard) {
            header
            Divider()
            TabView(selection: $selectedTab) {
                statusTab
                    .tabItem { Label("Status", systemImage: "antenna.radiowaves.left.and.right") }
                    .tag(WorkspaceTab.status)
                activityTab
                    .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
                    .tag(WorkspaceTab.activity)
                spotsTab
                    .tabItem { Label("Spots", systemImage: "scope") }
                    .tag(WorkspaceTab.spots)
                stationTab
                    .tabItem { Label("Station", systemImage: "antenna.radiowaves.left.and.right.circle") }
                    .tag(WorkspaceTab.station)
                configurationTab
                    .tabItem { Label("Configuration", systemImage: "slider.horizontal.3") }
                    .tag(WorkspaceTab.configuration)
            }
        }
        .padding(Layout.generous)
        .frame(minWidth: 760, idealWidth: 900, maxWidth: 1_040, minHeight: 520, idealHeight: 620)
    }

    private var header: some View {
        HStack(spacing: Layout.standard) {
            VStack(alignment: .leading, spacing: Layout.tight) {
                Text("OM0RX-xCat")
                    .font(.title2.bold())
                Text("FlexRadio CAT and RigCtlD bridge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .layoutPriority(1)

            Spacer(minLength: Layout.standard)

            HStack(spacing: Layout.compact) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(connectionLabel)
                        .font(.headline)
                    Text(model.configuration.connectionKind.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            if model.isRunning, model.configuration.connectionKind == .remoteAgent {
                Button("Reconnect") { model.reconnectRemoteAgent() }
                    .help("Re-establish the Remote Agent HTTPS and WebSocket connection")
            }
            Button(model.isRunning ? "Stop" : "Start") {
                model.isRunning ? model.stop() : model.start()
            }
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
    }

    private var statusTab: some View {
        VStack(alignment: .leading, spacing: Layout.standard) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Layout.standard) {
                    radioOverview
                    equipmentOverview
                }
                VStack(alignment: .leading, spacing: Layout.standard) {
                    radioOverview
                    equipmentOverview
                }
            }

            if model.configuration.connectionKind == .remoteAgent {
                remoteStationControls
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Layout.compact)
    }

    private var radioOverview: some View {
        GroupBox("Radio") {
            VStack(alignment: .leading, spacing: Layout.compact) {
                Label(connectionLabel, systemImage: connectionSymbol)
                    .foregroundStyle(connectionColor)
                Text(model.status)
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Layout.tight)
            .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
    }

    private var equipmentOverview: some View {
        GroupBox("Station path") {
            VStack(alignment: .leading, spacing: Layout.compact) {
                if let station = model.remoteStationStatus {
                    Grid(alignment: .leading, horizontalSpacing: Layout.standard, verticalSpacing: Layout.tight) {
                        statusRow("Amplifier", station.kpaSummary)
                        statusRow("Tuner", station.katSummary)
                        statusRow("Route", station.routeSummary)
                        statusRow("Alarms", station.alarmSummary)
                    }
                } else {
                    Text("Waiting for authoritative station state")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Layout.tight)
            .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func statusRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .help(value)
        }
    }

    private var remoteStationControls: some View {
        GroupBox("Remote control") {
            VStack(alignment: .leading, spacing: Layout.standard) {
                HStack(spacing: Layout.compact) {
                    Label(
                        model.configuration.allowCATTransmit ? "Full control enabled" : "Full control disabled",
                        systemImage: model.configuration.allowCATTransmit ? "checkmark.circle.fill" : "pause.circle"
                    )
                    .foregroundStyle(model.configuration.allowCATTransmit ? Color.green : Color.secondary)
                    Spacer()
                    if let station = model.remoteStationStatus, !station.inhibitors.isEmpty {
                        Text("Agent advisory: \(station.inhibitors.joined(separator: "; "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(station.inhibitors.joined(separator: "; "))
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: Layout.standard) {
                        offsetControl(
                            label: "RIT",
                            isOn: $model.remoteRITEnabled,
                            offset: $model.remoteRITOffsetHz,
                            actionLabel: "Apply RIT",
                            action: model.applyRemoteRIT
                        )
                        Divider().frame(height: 24)
                        offsetControl(
                            label: "XIT",
                            isOn: $model.remoteXITEnabled,
                            offset: $model.remoteXITOffsetHz,
                            actionLabel: "Apply XIT",
                            action: model.applyRemoteXIT
                        )
                    }
                    VStack(alignment: .leading, spacing: Layout.compact) {
                        offsetControl(
                            label: "RIT",
                            isOn: $model.remoteRITEnabled,
                            offset: $model.remoteRITOffsetHz,
                            actionLabel: "Apply RIT",
                            action: model.applyRemoteRIT
                        )
                        offsetControl(
                            label: "XIT",
                            isOn: $model.remoteXITEnabled,
                            offset: $model.remoteXITOffsetHz,
                            actionLabel: "Apply XIT",
                            action: model.applyRemoteXIT
                        )
                    }
                }
                .disabled(!model.isRadioConnected || !model.configuration.allowCATTransmit)

                HStack(spacing: Layout.compact) {
                    TextField("RF power W", value: $model.remoteRFPowerWatts, format: .number)
                        .frame(width: 118)
                    Button("Apply power") { model.applyRemoteRFPower() }
                        .disabled(!model.isRadioConnected || !model.configuration.allowCATTransmit)
                    Spacer()
                    ForEach(RemoteStationAction.allCases, id: \.self) { action in
                        Button(action.rawValue.capitalized) { model.performRemoteStationAction(action) }
                            .disabled(!model.remoteActionAllowed(action))
                    }
                }
            }
            .padding(Layout.tight)
        }
    }

    private func offsetControl(
        label: String,
        isOn: Binding<Bool>,
        offset: Binding<Int>,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Layout.compact) {
            Toggle(label, isOn: isOn)
                .toggleStyle(.checkbox)
            TextField("Hz", value: offset, format: .number)
                .frame(width: Layout.compactFieldWidth)
            Button(actionLabel, action: action)
        }
    }

    private var activityTab: some View {
        VStack(alignment: .leading, spacing: Layout.standard) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Layout.tight) {
                    Text("Recent activity")
                        .font(.headline)
                    Text("Newest events appear last. Showing up to 18 entries.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.events.count) total")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Divider()
            if model.events.isEmpty {
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "waveform.path",
                    description: Text("Start the bridge to see connection and CAT events.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(model.events.suffix(18).joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(Layout.standard)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.top, Layout.compact)
    }

    private var configurationTab: some View {
        VStack(alignment: .leading, spacing: Layout.standard) {
            GroupBox("Connection") {
                connectionSettings
                    .padding(Layout.tight)
            }
            GroupBox("Local services") {
                Grid(alignment: .leading, horizontalSpacing: Layout.standard, verticalSpacing: Layout.compact) {
                    configurationRow("CAT port") {
                        TextField("CAT port", value: $model.configuration.catPort, format: .number)
                    }
                    configurationRow("RigCtlD port") {
                        TextField("RigCtlD port", value: $model.configuration.rigCtlPort, format: .number)
                    }
                    GridRow {
                        Text("Control")
                            .foregroundStyle(.secondary)
                        Toggle("Enable full CAT and station control", isOn: $model.configuration.allowCATTransmit)
                    }
                    GridRow {
                        Text("Startup")
                            .foregroundStyle(.secondary)
                        Toggle("Start protocol servers automatically", isOn: $model.configuration.launchServersAutomatically)
                    }
                }
                .padding(Layout.tight)
            }
            HStack {
                Text(configurationGuidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Save Settings") { model.save() }
                    .keyboardShortcut("s", modifiers: .command)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Layout.compact)
        .disabled(model.isRunning)
    }

    private var spotsTab: some View {
        VStack(alignment: .leading, spacing: Layout.compact) {
            HStack(alignment: .top, spacing: Layout.standard) {
                GroupBox("RUMlog inputs") {
                    Grid(alignment: .leading, horizontalSpacing: Layout.standard, verticalSpacing: Layout.compact) {
                        GridRow {
                            Toggle("Enable", isOn: $model.configuration.spotBridge.enabled)
                                .toggleStyle(.checkbox)
                                .onChange(of: model.configuration.spotBridge.enabled) { _, _ in
                                    model.restartSpotBridge()
                                }
                            Text(model.spotBridgeStatus)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        GridRow {
                            Text("Logbook UDP")
                                .foregroundStyle(.secondary)
                            TextField("Port", value: $model.configuration.spotBridge.logbookPort, format: .number)
                                .frame(width: 88)
                        }
                        GridRow {
                            Text("Contest UDP")
                                .foregroundStyle(.secondary)
                            TextField("Port", value: $model.configuration.spotBridge.contestPort, format: .number)
                                .frame(width: 88)
                        }
                    }
                    .padding(Layout.tight)
                }
                .frame(maxWidth: .infinity)

                GroupBox("Live activity") {
                    VStack(alignment: .leading, spacing: Layout.compact) {
                        HStack(spacing: Layout.standard) {
                            spotMetric("Received", model.spotsReceived)
                            spotMetric("Forwarded", model.spotsForwarded)
                            spotMetric("Rejected", model.spotsRejected)
                        }
                        Divider()
                        Text(model.lastSpotSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(Layout.tight)
                }
                .frame(maxWidth: .infinity)
            }

            HStack {
                Text("Spot styling")
                    .font(.headline)
                Spacer()
                Picker("Rule set", selection: $selectedSpotFeed) {
                    ForEach(SpotFeed.allCases, id: \.self) { feed in
                        Text(feed.rawValue).tag(feed)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: Layout.standard, verticalSpacing: 6) {
                    GridRow {
                        Text("Category").foregroundStyle(.secondary)
                        Text("Priority").foregroundStyle(.secondary)
                        Text("Color").foregroundStyle(.secondary)
                        Text("Lifetime").foregroundStyle(.secondary)
                    }
                    Divider().gridCellColumns(4)
                    ForEach(DXSpotCategory.categories(for: selectedSpotFeed), id: \.self) { category in
                        GridRow {
                            Text(category.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Picker("Priority", selection: spotPriorityBinding(category)) {
                                ForEach(1...5, id: \.self) { Text("Priority \($0)").tag($0) }
                            }
                            .labelsHidden()
                            .accessibilityLabel("\(category.title) priority")
                            .frame(width: 116)
                            ColorPicker("Color", selection: spotColorBinding(category), supportsOpacity: false)
                                .labelsHidden()
                                .accessibilityLabel("\(category.title) color")
                                .frame(width: 44)
                            Picker("Lifetime", selection: spotLifetimeBinding(category)) {
                                ForEach([180, 300, 600, 900, 1_200, 1_800, 3_600], id: \.self) {
                                    Text(lifetimeLabel($0)).tag($0)
                                }
                            }
                            .labelsHidden()
                            .accessibilityLabel("\(category.title) lifetime")
                            .frame(width: 110)
                        }
                    }
                }
                .padding(Layout.tight)
            }

            HStack {
                Label("Spot markers only — this bridge never keys PTT or transmits RF.", systemImage: "shield.checkered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.isRunning ? "Apply & Restart Listener" : "Save Spot Settings") {
                    model.restartSpotBridge()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Layout.compact)
    }

    private func spotMetric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title3.monospacedDigit().bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func spotPriorityBinding(_ category: DXSpotCategory) -> Binding<Int> {
        Binding(
            get: { model.configuration.spotBridge.style(for: category).priority },
            set: { value in
                var style = model.configuration.spotBridge.style(for: category)
                style.priority = value
                model.configuration.spotBridge.setStyle(style, for: category)
            }
        )
    }

    private func spotLifetimeBinding(_ category: DXSpotCategory) -> Binding<Int> {
        Binding(
            get: { model.configuration.spotBridge.style(for: category).lifetimeSeconds },
            set: { value in
                var style = model.configuration.spotBridge.style(for: category)
                style.lifetimeSeconds = value
                model.configuration.spotBridge.setStyle(style, for: category)
            }
        )
    }

    private func spotColorBinding(_ category: DXSpotCategory) -> Binding<Color> {
        Binding(
            get: { color(hex: model.configuration.spotBridge.style(for: category).colorHex) },
            set: { value in
                var style = model.configuration.spotBridge.style(for: category)
                style.colorHex = hex(color: value)
                model.configuration.spotBridge.setStyle(style, for: category)
            }
        )
    }

    private func lifetimeLabel(_ seconds: Int) -> String {
        seconds < 3_600 ? "\(seconds / 60) min" : "1 hour"
    }

    private func color(hex: String) -> Color {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard raw.count == 6, let value = Int(raw, radix: 16) else { return .blue }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private func hex(color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return "#0A84FF" }
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }

    @ViewBuilder
    private var stationTab: some View {
        if model.configuration.connectionKind != .remoteAgent {
            ContentUnavailableView(
                "Remote station settings unavailable",
                systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                description: Text("Select Remote Station Agent in Configuration to edit Windows station policy.")
            )
        } else {
            VStack(alignment: .leading, spacing: Layout.compact) {
                HStack(alignment: .top, spacing: Layout.standard) {
                    GroupBox("FLEX-8400") {
                        Grid(alignment: .leading, horizontalSpacing: Layout.compact, verticalSpacing: 6) {
                            GridRow {
                                Text("Station").foregroundStyle(.secondary)
                                TextField("Maestro", text: $model.remoteConfiguration.flex.stationName)
                                    .frame(width: 118)
                            }
                            GridRow {
                                Text("Host").foregroundStyle(.secondary)
                                TextField("Radio IP", text: $model.remoteConfiguration.flex.host)
                                    .frame(width: 118)
                            }
                            GridRow {
                                Text("TCP / slice").foregroundStyle(.secondary)
                                HStack(spacing: Layout.tight) {
                                    TextField("Port", value: $model.remoteConfiguration.flex.port, format: .number)
                                        .frame(width: 70)
                                    TextField("Slice", value: $model.remoteConfiguration.flex.sliceID, format: .number)
                                        .frame(width: 44)
                                }
                            }
                            GridRow {
                                Toggle("Enforce antenna policy", isOn: $model.remoteConfiguration.policy.flexAntenna.enabled)
                                    .gridCellColumns(2)
                            }
                        }
                        .padding(Layout.tight)
                    }
                    .frame(maxWidth: .infinity)

                    GroupBox("Hardware") {
                        Grid(alignment: .leading, horizontalSpacing: Layout.compact, verticalSpacing: 6) {
                            GridRow {
                                Toggle("KPA500", isOn: $model.remoteConfiguration.kpa500.enabled)
                                TextField("COM port", text: $model.remoteConfiguration.kpa500.port).frame(width: 84)
                                TextField("Baud", value: $model.remoteConfiguration.kpa500.baudrate, format: .number).frame(width: 78)
                            }
                            GridRow {
                                Toggle("KAT500", isOn: $model.remoteConfiguration.kat500.enabled)
                                TextField("COM port", text: $model.remoteConfiguration.kat500.port).frame(width: 84)
                                TextField("Baud", value: $model.remoteConfiguration.kat500.baudrate, format: .number).frame(width: 78)
                            }
                            GridRow {
                                Toggle("Follow FLEX", isOn: $model.remoteConfiguration.policy.followRadio)
                                Toggle("Commissioned", isOn: $model.remoteConfiguration.commissioned)
                                    .gridCellColumns(2)
                            }
                        }
                        .padding(Layout.tight)
                    }
                    .frame(maxWidth: .infinity)

                    GroupBox("Tune and digital") {
                        Grid(alignment: .leading, horizontalSpacing: Layout.compact, verticalSpacing: 6) {
                            GridRow {
                                Text("Tune W").foregroundStyle(.secondary)
                                TextField("W", value: $model.remoteConfiguration.policy.tunePowerW, format: .number).frame(width: 58)
                                Text("Target SWR").foregroundStyle(.secondary)
                                TextField("SWR", value: $model.remoteConfiguration.policy.tuneTargetSWR, format: .number).frame(width: 58)
                            }
                            GridRow {
                                Text("Abort SWR").foregroundStyle(.secondary)
                                TextField("SWR", value: $model.remoteConfiguration.policy.tuneAbortSWR, format: .number).frame(width: 58)
                                Text("Timeout s").foregroundStyle(.secondary)
                                TextField("Seconds", value: $model.remoteConfiguration.policy.tuneTimeoutSeconds, format: .number).frame(width: 58)
                            }
                            GridRow {
                                Text("Digital PA").foregroundStyle(.secondary)
                                Picker("Digital PA policy", selection: $model.remoteConfiguration.policy.digitalKPAPolicy) {
                                    Text("Operate").tag("operate")
                                    Text("Standby").tag("standby")
                                }
                                .labelsHidden()
                                .gridCellColumns(3)
                            }
                        }
                        .padding(Layout.tight)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(!model.remoteConfigurationLoaded || model.remoteConfigurationBusy)

                HStack {
                    Text("Band routing and drive")
                        .font(.headline)
                    Spacer()
                    ForEach(1...3, id: \.self) { antenna in
                        TextField(
                            "ANT\(antenna) name",
                            text: remoteAntennaNameBinding(antenna)
                        )
                        .frame(width: 108)
                    }
                }
                .disabled(!model.remoteConfigurationLoaded || model.remoteConfigurationBusy)

                GroupBox {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                        GridRow {
                            Text("Band")
                            Text("FLEX TX")
                            Text("KAT out")
                            Text("PA")
                            Text("PA W")
                            Text("Bare W")
                            Text("Digital PA")
                            Text("Digital W")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Divider().gridCellColumns(8)
                        ForEach(RemoteStationConfiguration.bands, id: \.self) { band in
                            GridRow {
                                Text(band).font(.body.monospacedDigit())
                                Picker("\(band) FLEX TX antenna", selection: remoteFlexAntennaBinding(band)) {
                                    ForEach(["ANT1", "ANT2", "XVTR"], id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden().frame(width: 82)
                                Picker("\(band) KAT output", selection: remoteKATAntennaBinding(band)) {
                                    ForEach(1...3, id: \.self) { Text("ANT\($0)").tag($0) }
                                }
                                .labelsHidden().frame(width: 76)
                                Toggle("\(band) amplifier allowed", isOn: remoteBandMembershipBinding(band, digital: false))
                                    .labelsHidden()
                                TextField("PA W", value: remotePowerBinding(band, kind: .amplifier), format: .number).frame(width: 58)
                                TextField("Barefoot W", value: remotePowerBinding(band, kind: .barefoot), format: .number).frame(width: 58)
                                Toggle("\(band) digital amplifier allowed", isOn: remoteBandMembershipBinding(band, digital: true))
                                    .labelsHidden()
                                TextField("Digital W", value: remotePowerBinding(band, kind: .digital), format: .number).frame(width: 64)
                            }
                        }
                    }
                    .padding(Layout.tight)
                }
                .disabled(!model.remoteConfigurationLoaded || model.remoteConfigurationBusy)

                HStack {
                    Text(model.remoteConfigurationStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button("Reload from Windows") { model.reloadRemoteConfiguration() }
                        .disabled(model.remoteConfigurationBusy || !model.isRunning)
                    Button("Save to Windows") { model.saveRemoteConfiguration() }
                        .disabled(model.remoteConfigurationBusy || !model.remoteConfigurationLoaded)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, Layout.compact)
        }
    }

    private enum RemotePowerKind {
        case amplifier
        case barefoot
        case digital
    }

    private func remoteFlexAntennaBinding(_ band: String) -> Binding<String> {
        Binding(
            get: { model.remoteConfiguration.policy.flexAntenna.bands[band] ?? "ANT1" },
            set: { model.remoteConfiguration.policy.flexAntenna.bands[band] = $0 }
        )
    }

    private func remoteKATAntennaBinding(_ band: String) -> Binding<Int> {
        Binding(
            get: { model.remoteConfiguration.policy.katAntenna[band] ?? 1 },
            set: { model.remoteConfiguration.policy.katAntenna[band] = $0 }
        )
    }

    private func remoteAntennaNameBinding(_ antenna: Int) -> Binding<String> {
        let key = String(antenna)
        return Binding(
            get: { model.remoteConfiguration.policy.katAntennaNames[key] ?? "KAT ANT\(antenna)" },
            set: { model.remoteConfiguration.policy.katAntennaNames[key] = $0 }
        )
    }

    private func remoteBandMembershipBinding(_ band: String, digital: Bool) -> Binding<Bool> {
        Binding(
            get: {
                let bands = digital
                    ? model.remoteConfiguration.policy.digitalAmplifierAllowedBands
                    : model.remoteConfiguration.policy.amplifierAllowedBands
                return bands.contains(band)
            },
            set: { enabled in
                var bands = digital
                    ? model.remoteConfiguration.policy.digitalAmplifierAllowedBands
                    : model.remoteConfiguration.policy.amplifierAllowedBands
                bands.removeAll { $0 == band }
                if enabled { bands.append(band) }
                bands.sort { lhs, rhs in
                    (RemoteStationConfiguration.bands.firstIndex(of: lhs) ?? .max)
                        < (RemoteStationConfiguration.bands.firstIndex(of: rhs) ?? .max)
                }
                if digital {
                    model.remoteConfiguration.policy.digitalAmplifierAllowedBands = bands
                } else {
                    model.remoteConfiguration.policy.amplifierAllowedBands = bands
                }
            }
        )
    }

    private func remotePowerBinding(_ band: String, kind: RemotePowerKind) -> Binding<Int> {
        Binding(
            get: {
                switch kind {
                case .amplifier: model.remoteConfiguration.policy.amplifierDriveW[band] ?? 25
                case .barefoot: model.remoteConfiguration.policy.barefootDriveW[band] ?? 25
                case .digital: model.remoteConfiguration.policy.digitalAmplifierDriveW[band] ?? 25
                }
            },
            set: { value in
                switch kind {
                case .amplifier: model.remoteConfiguration.policy.amplifierDriveW[band] = value
                case .barefoot: model.remoteConfiguration.policy.barefootDriveW[band] = value
                case .digital: model.remoteConfiguration.policy.digitalAmplifierDriveW[band] = value
                }
            }
        )
    }

    @ViewBuilder
    private var connectionSettings: some View {
        Grid(alignment: .leading, horizontalSpacing: Layout.standard, verticalSpacing: Layout.compact) {
            configurationRow("Radio connection") {
                Picker("Radio connection", selection: $model.configuration.connectionKind) {
                    ForEach(AppConfiguration.ConnectionKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .labelsHidden()
            }

            switch model.configuration.connectionKind {
            case .remoteAgent:
                configurationRow("Agent HTTPS URL") {
                    TextField("https://station.tailnet.ts.net", text: $model.configuration.remoteAgentBaseURL)
                        .textContentType(.URL)
                }
                configurationRow("Bearer token") {
                    HStack {
                        SecureField("Stored securely in Keychain", text: $model.remoteAgentToken)
                            .textContentType(.password)
                        Button("Forget saved token") { model.forgetRemoteAgentToken() }
                    }
                }
            case .smartLink:
                configurationRow("SmartLink email") {
                    TextField("Email", text: $model.configuration.smartLinkEmail)
                        .textContentType(.username)
                }
                configurationRow("Password") {
                    SecureField("Needed once", text: $model.smartLinkPassword)
                        .textContentType(.password)
                }
                configurationRow("Radio serial") {
                    HStack {
                        TextField("Optional preferred serial", text: $model.configuration.smartLinkRadioSerial)
                        Button("Forget session") { model.forgetSmartLinkSession() }
                        Button("Reset pin") { model.resetSmartLinkCertificatePin() }
                    }
                }
                stationAndSliceRows
            case .local:
                configurationRow("Radio host") {
                    TextField("IP address or hostname", text: $model.configuration.radioHost)
                }
                stationAndSliceRows
            case .legacyXCAT:
                configurationRow("xCAT host") {
                    TextField("Host", text: $model.configuration.legacyXCATHost)
                }
                configurationRow("xCAT CAT port") {
                    TextField("Port", value: $model.configuration.legacyXCATPort, format: .number)
                }
                GridRow {
                    Text("Supervision")
                        .foregroundStyle(.secondary)
                    Toggle("Restart xCAT automatically if it crashes", isOn: $model.configuration.superviseLegacyXCAT)
                }
            case .simulator:
                stationAndSliceRows
            }
        }
    }

    @ViewBuilder
    private var stationAndSliceRows: some View {
        configurationRow("Station") {
            HStack {
                TextField("Station name", text: $model.configuration.stationName)
                Text("Slice")
                    .foregroundStyle(.secondary)
                TextField("A", text: $model.configuration.sliceLetter)
                    .frame(width: 64)
            }
        }
    }

    private func configurationRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: Layout.labelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var connectionLabel: String {
        if model.isRadioConnected { return "Connected" }
        if model.isRunning { return "Connecting" }
        return "Stopped"
    }

    private var connectionColor: Color {
        if model.isRadioConnected { return .green }
        if model.isRunning { return .orange }
        return .secondary
    }

    private var connectionSymbol: String {
        if model.isRadioConnected { return "checkmark.circle.fill" }
        if model.isRunning { return "arrow.triangle.2.circlepath" }
        return "stop.circle"
    }

    private var configurationGuidance: String {
        switch model.configuration.connectionKind {
        case .remoteAgent:
            "The bearer token is stored in macOS Keychain. All radio and station commands go through the Windows agent."
        case .smartLink:
            "The password remains in memory; refresh credentials and the radio certificate pin are stored in Keychain."
        case .legacyXCAT:
            "RUMlogNG → OM0RX-xCat → xCAT → SmartLink → FlexRadio"
        default:
            "CAT and RigCtlD listeners bind only to this Mac's loopback interface."
        }
    }
}
