// Copyright © 2026 Oliver Bross OM0RX
// SPDX-License-Identifier: GPL-3.0-only

import MapKit
import SwiftUI
import XCatCore

struct RotatorSettingsView: View {
    @EnvironmentObject private var model: AppModel

    private let cyan = Color(red: 0.40, green: 0.91, blue: 0.98)
    private let green = Color(red: 0.43, green: 0.91, blue: 0.72)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(model.rotatorConnectionState == .connected ? green : .orange)
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.rotatorStatus).font(.headline)
                    Text(model.rotatorFeedStatus).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.rotatorConnectionState == .stopped || model.rotatorConnectionState == .failed {
                    Button("Connect") { model.startRotator() }
                } else {
                    Button("Disconnect") { model.stopRotator() }
                }
                Button("Save & Reconnect") { model.saveRotatorSettingsAndReconnect() }
                    .buttonStyle(.borderedProminent)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 12) {
                    GroupBox("Controller") {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                            GridRow {
                                Text("Enabled")
                                Toggle("", isOn: $model.configuration.rotator.enabled).labelsHidden()
                                Text("Connect at launch")
                                Toggle("", isOn: $model.configuration.rotator.connectAtLaunch).labelsHidden()
                            }
                            GridRow {
                                Text("Name")
                                TextField("ARCO", text: $model.configuration.rotator.name)
                                Text("Protocol")
                                Text("DCU-1").foregroundStyle(cyan)
                            }
                            GridRow {
                                Text("TCP host")
                                TextField("Rotator host or IP", text: $model.configuration.rotator.host)
                                    .textFieldStyle(.roundedBorder)
                                Text("Port")
                                TextField("4001", value: portBinding, format: .number.grouping(.never))
                                    .frame(width: 76)
                            }
                            GridRow {
                                Text("Poll rate")
                                Picker("", selection: $model.configuration.rotator.pollIntervalMilliseconds) {
                                    Text("100 ms").tag(100)
                                    Text("250 ms").tag(250)
                                    Text("500 ms").tag(500)
                                    Text("1 s").tag(1_000)
                                }
                                .labelsHidden()
                                Text("RUMlog UDP")
                                TextField("12064", value: udpPortBinding, format: .number.grouping(.never))
                                    .frame(width: 76)
                            }
                        }
                        .padding(6)
                    }

                    GroupBox("Target & manual control") {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                TextField("Bearing, Maidenhead grid, or callsign", text: $model.rotatorTargetInput)
                                    .onSubmit { model.resolveRotatorTarget() }
                                Button("Resolve") { model.resolveRotatorTarget() }
                                Button("Turn") { model.turnRotatorToTarget() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(model.rotatorTargetBearing == nil || model.rotatorConnectionState != .connected)
                                Button("Long path") { model.toggleRotatorPath() }
                                    .disabled(model.rotatorTargetBearing == nil)
                                Button("Stop") { model.stopRotatorMotion() }
                                    .tint(.red)
                                    .disabled(model.rotatorConnectionState != .connected)
                            }
                            HStack {
                                Text(model.rotatorTargetLabel).font(.headline)
                                if let bearing = model.rotatorTargetBearing {
                                    Text("\(Int(bearing.rounded()))°").font(.headline.monospacedDigit()).foregroundStyle(cyan)
                                }
                                Text(model.rotatorTargetSource).font(.caption).foregroundStyle(.secondary)
                            }
                            TextField("Optional callsign,grid CSV path", text: $model.configuration.rotator.callsignDatabasePath)
                                .font(.caption)
                        }
                        .padding(6)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    GroupBox("Location & automatic turning") {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                            GridRow {
                                Text("Home grid")
                                TextField("JN88UQ", text: $model.configuration.rotator.homeGrid)
                                    .textCase(.uppercase)
                                    .frame(width: 110)
                                Text(MaidenheadLocator.coordinate(from: model.configuration.rotator.homeGrid) == nil ? "Invalid" : "Valid")
                                    .foregroundStyle(MaidenheadLocator.coordinate(from: model.configuration.rotator.homeGrid) == nil ? .orange : green)
                            }
                            GridRow {
                                Text("Auto turn")
                                Toggle("", isOn: $model.configuration.rotator.automaticTurningEnabled).labelsHidden()
                                Picker("", selection: $model.configuration.rotator.automaticSource) {
                                    ForEach(RotatorAutomaticSource.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }
                                .labelsHidden()
                            }
                            GridRow {
                                Text("Minimum change")
                                TextField("0", value: $model.configuration.rotator.minimumAutomaticTurnDegrees, format: .number)
                                    .frame(width: 64)
                                Text("degrees (0 = always)").font(.caption).foregroundStyle(.secondary)
                            }
                            GridRow {
                                Text("Beam width")
                                TextField("5", value: $model.configuration.rotator.beamWidthDegrees, format: .number)
                                    .frame(width: 64)
                                Text("degrees").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(6)
                    }

                    GroupBox("Bands, offsets & bidirectional antennas") {
                        HStack(alignment: .top, spacing: 16) {
                            bandColumn(Array(RotatorConfiguration.supportedBands.prefix(8)))
                            Divider()
                            bandColumn(Array(RotatorConfiguration.supportedBands.dropFirst(8)))
                        }
                        .padding(6)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var portBinding: Binding<Int> {
        Binding(get: { Int(model.configuration.rotator.port) }, set: { model.configuration.rotator.port = UInt16(clamping: $0) })
    }

    private var udpPortBinding: Binding<Int> {
        Binding(get: { Int(model.configuration.rotator.rumlogPort) }, set: { model.configuration.rotator.rumlogPort = UInt16(clamping: $0) })
    }

    private func setBinding(_ band: String, keyPath: WritableKeyPath<RotatorConfiguration, Set<String>>) -> Binding<Bool> {
        Binding(
            get: { model.configuration.rotator[keyPath: keyPath].contains(band) },
            set: { enabled in
                if enabled { model.configuration.rotator[keyPath: keyPath].insert(band) }
                else { model.configuration.rotator[keyPath: keyPath].remove(band) }
            }
        )
    }

    private func offsetBinding(_ band: String) -> Binding<Int> {
        Binding(
            get: { model.configuration.rotator.bandOffsets[band] ?? 0 },
            set: { model.configuration.rotator.bandOffsets[band] = min(max($0, -180), 180) }
        )
    }

    private func bandColumn(_ bands: [String]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                Text("Band").font(.caption2.bold())
                Text("Use").font(.caption2.bold())
                Text("Offset").font(.caption2.bold())
                Text("Bi-dir").font(.caption2.bold())
            }
            ForEach(bands, id: \.self) { band in
                GridRow {
                    Text(band).font(.system(.caption, design: .monospaced)).frame(width: 34, alignment: .leading)
                    Toggle("Use \(band)", isOn: setBinding(band, keyPath: \.enabledBands))
                        .labelsHidden()
                    TextField("0", value: offsetBinding(band), format: .number)
                        .frame(width: 44)
                    Toggle("Bidirectional \(band)", isOn: setBinding(band, keyPath: \.bidirectionalBands))
                        .labelsHidden()
                }
            }
        }
    }
}

struct RotatorMonitorPanel: View {
    @EnvironmentObject private var model: AppModel

    private let cyan = Color(red: 0.40, green: 0.91, blue: 0.98)
    private let magenta = Color(red: 0.75, green: 0.35, blue: 0.95)
    private let green = Color(red: 0.43, green: 0.91, blue: 0.72)

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.configuration.rotator.name.uppercased())
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(cyan)
                    Text(model.rotatorStatus)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Label(connectionLabel, systemImage: connectionSymbol)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(connectionTint)
            }

            RotatorCompass(
                azimuth: model.rotatorAzimuth,
                target: model.rotatorTargetBearing,
                beamWidth: Double(model.configuration.rotator.beamWidthDegrees),
                isMoving: model.rotatorIsMoving
            )
            .frame(height: 176)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.rotatorTargetLabel)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(magenta)
                    Text(targetDetail)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let target = model.rotatorTargetBearing {
                    Text(String(format: "%03.0f°", target))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(magenta)
                }
            }

            RotatorMapInset(home: model.rotatorHomeCoordinate, target: model.rotatorTargetCoordinate)
                .frame(height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(cyan.opacity(0.22)))

            HStack(spacing: 7) {
                Text(model.currentBand)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(cyan)
                Text(model.rotatorFeedStatus)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("↺") { model.rotateRotator(clockwise: false) }
                    .help("Rotate counter-clockwise")
                    .disabled(model.rotatorConnectionState != .connected)
                Button("Turn") { model.turnRotatorToTarget() }
                    .disabled(model.rotatorTargetBearing == nil || model.rotatorConnectionState != .connected)
                Button("↻") { model.rotateRotator(clockwise: true) }
                    .help("Rotate clockwise")
                    .disabled(model.rotatorConnectionState != .connected)
                Button("Stop") { model.stopRotatorMotion() }
                    .disabled(model.rotatorConnectionState != .connected)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 354)
        .background(Color(red: 0.02, green: 0.045, blue: 0.075))
    }

    private var connectionLabel: String {
        switch model.rotatorConnectionState {
        case .connected: model.rotatorIsMoving ? "MOVING" : "READY"
        case .connecting: "CONNECTING"
        case .reconnecting: "RETRYING"
        case .failed: "ERROR"
        case .stopped: "OFFLINE"
        }
    }

    private var connectionSymbol: String {
        model.rotatorConnectionState == .connected ? "location.north.circle.fill" : "location.slash.circle"
    }

    private var connectionTint: Color {
        model.rotatorConnectionState == .connected ? green : .orange
    }

    private var targetDetail: String {
        let distance = model.rotatorTargetDistanceKilometers.map { " · \(Int($0.rounded())) km" } ?? ""
        return "\(model.rotatorTargetSource)\(distance)"
    }
}

private struct RotatorCompass: View {
    let azimuth: Double?
    let target: Double?
    let beamWidth: Double
    let isMoving: Bool

    private let cyan = Color(red: 0.40, green: 0.91, blue: 0.98)
    private let magenta = Color(red: 0.75, green: 0.35, blue: 0.95)

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.cyan.opacity(0.10), Color.black.opacity(0.36)], center: .center, startRadius: 8, endRadius: side / 2))
                Circle().stroke(cyan.opacity(0.35), lineWidth: 1)
                ForEach(0..<36, id: \.self) { tick in
                    Capsule()
                        .fill(tick.isMultiple(of: 9) ? cyan : cyan.opacity(0.38))
                        .frame(width: tick.isMultiple(of: 9) ? 2 : 1, height: tick.isMultiple(of: 3) ? 10 : 6)
                        .offset(y: -side / 2 + 9)
                        .rotationEffect(.degrees(Double(tick) * 10))
                }
                cardinal("N", angle: 0, side: side)
                cardinal("E", angle: 90, side: side)
                cardinal("S", angle: 180, side: side)
                cardinal("W", angle: 270, side: side)

                if let target {
                    RotatorBeamShape(bearing: target, width: beamWidth)
                        .fill(magenta.opacity(0.19))
                    bearingNeedle(target, color: magenta, length: side * 0.42, width: 2)
                }
                if let azimuth {
                    bearingNeedle(azimuth, color: cyan, length: side * 0.38, width: 4)
                    Text(String(format: "%03.0f°", azimuth))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(cyan)
                } else {
                    Text("---°")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Circle().fill(isMoving ? Color.orange : cyan).frame(width: 9, height: 9)
                    .shadow(color: (isMoving ? Color.orange : cyan).opacity(0.8), radius: 5)
            }
            .frame(width: side, height: side)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Antenna azimuth")
        .accessibilityValue(azimuth.map { "\(Int($0.rounded())) degrees" } ?? "Unavailable")
    }

    private func bearingNeedle(_ bearing: Double, color: Color, length: CGFloat, width: CGFloat) -> some View {
        Capsule()
            .fill(LinearGradient(colors: [color.opacity(0.25), color], startPoint: .bottom, endPoint: .top))
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(bearing))
    }

    private func cardinal(_ text: String, angle: Double, side: CGFloat) -> some View {
        let radians = angle * .pi / 180
        let radius = side / 2 - 23
        return Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(cyan.opacity(0.82))
            .offset(x: sin(radians) * radius, y: -cos(radians) * radius)
    }
}

private struct RotatorBeamShape: Shape {
    let bearing: Double
    let width: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.48
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(bearing - width / 2 - 90),
            endAngle: .degrees(bearing + width / 2 - 90),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct RotatorMapInset: View {
    let home: GeoCoordinate?
    let target: GeoCoordinate?

    private let world = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 12, longitude: 20),
        span: MKCoordinateSpan(latitudeDelta: 150, longitudeDelta: 340)
    )

    var body: some View {
        Map(initialPosition: .region(world), interactionModes: []) {
            if let home {
                Annotation("Home", coordinate: coordinate(home)) {
                    Circle().fill(.cyan).frame(width: 8, height: 8).shadow(color: .cyan, radius: 4)
                }
            }
            if let target {
                Marker("Target", coordinate: coordinate(target)).tint(.purple)
            }
            if let home, let target {
                MapPolyline(coordinates: [coordinate(home), coordinate(target)])
                    .stroke(.purple, lineWidth: 2)
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .allowsHitTesting(false)
    }

    private func coordinate(_ value: GeoCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: value.latitude, longitude: value.longitude)
    }
}
