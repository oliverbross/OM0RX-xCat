import Foundation
import Testing
@testable import XCatCore

@Test func maidenheadLocatorUsesCellCentre() {
    let coordinate = MaidenheadLocator.coordinate(from: "JN88UQ")
    #expect(coordinate != nil)
    #expect(abs((coordinate?.latitude ?? 0) - 48.6875) < 0.001)
    #expect(abs((coordinate?.longitude ?? 0) - 17.708333) < 0.001)
    #expect(MaidenheadLocator.coordinate(from: "NOT-A-GRID") == nil)
}

@Test func bearingDistanceAndDestinationAreConsistent() {
    let home = GeoCoordinate(latitude: 48.6875, longitude: 17.708333)
    let east = GeoCoordinate(latitude: 48.6875, longitude: 18.708333)
    let bearing = RotatorGeometry.initialBearing(from: home, to: east)
    #expect(bearing > 89 && bearing < 91)
    #expect(RotatorGeometry.distanceKilometers(from: home, to: east) > 70)
    #expect(RotatorGeometry.shortestDifference(from: 350, to: 10) == 20)
    #expect(RotatorGeometry.shortestDifference(from: 10, to: 350) == -20)
    let destination = RotatorGeometry.destination(from: home, bearing: 90, distanceKilometers: 100)
    #expect(destination.longitude > home.longitude)
}

@Test func compassClickCoordinatesProduceCardinalBearings() {
    #expect(RotatorGeometry.bearingForDialPoint(x: 100, y: 0, centerX: 100, centerY: 100, radius: 100) == 0)
    #expect(RotatorGeometry.bearingForDialPoint(x: 200, y: 100, centerX: 100, centerY: 100, radius: 100) == 90)
    #expect(RotatorGeometry.bearingForDialPoint(x: 100, y: 200, centerX: 100, centerY: 100, radius: 100) == 180)
    #expect(RotatorGeometry.bearingForDialPoint(x: 0, y: 100, centerX: 100, centerY: 100, radius: 100) == 270)
    #expect(RotatorGeometry.bearingForDialPoint(x: 100, y: 100, centerX: 100, centerY: 100, radius: 100) == nil)
    #expect(RotatorGeometry.bearingForDialPoint(x: 201, y: 100, centerX: 100, centerY: 100, radius: 100) == nil)
}

@Test func automaticTurnDeadbandIgnoresAtTargetJitter() {
    #expect(!RotatorGeometry.shouldAutomaticallyTurn(from: 250, to: 249, minimumChange: 0))
    #expect(!RotatorGeometry.shouldAutomaticallyTurn(from: 359.5, to: 0.5, minimumChange: 0))
    #expect(RotatorGeometry.shouldAutomaticallyTurn(from: 250, to: 248.9, minimumChange: 0))
    #expect(!RotatorGeometry.shouldAutomaticallyTurn(from: 250, to: 256, minimumChange: 10))
    #expect(RotatorGeometry.shouldAutomaticallyTurn(from: 250, to: 261, minimumChange: 10))
}

@Test func dcu1ProtocolCommandsAndResponses() {
    #expect(DCU1Protocol.pollCommand == "AI1;")
    #expect(DCU1Protocol.stopCommand == ";")
    #expect(DCU1Protocol.clockwiseCommand == "U")
    #expect(DCU1Protocol.counterclockwiseCommand == "D")
    #expect(DCU1Protocol.turnCommand(to: 7) == "AP1007;AM1;")
    #expect(DCU1Protocol.turnCommand(to: 361) == "AP1001;AM1;")
    #expect(DCU1Protocol.azimuths(in: ";093;") == [93])
    #expect(DCU1Protocol.azimuths(in: "271.5;") == [271.5])
    #expect(DCU1Protocol.azimuths(in: "garbage") == [])
}

@Test func rumlogRotorXMLUsesStationAndCountryBearings() throws {
    let xml = Data("""
        <AppInfo>
          <ShownDxcc>VK</ShownDxcc><HdgToDxcc>249</HdgToDxcc><ShownDxccLocation>OF88AA</ShownDxccLocation>
          <ShownStation>VK6ABC</ShownStation><HdgToStation>251</HdgToStation><ShownStationLocation>OF88AA</ShownStationLocation>
          <CurrentBand>20m</CurrentBand>
        </AppInfo>
        """.utf8)
    let update = try RUMlogRotatorParser.parse(xml)
    #expect(update.callsign == "VK6ABC")
    #expect(update.countryCode == "VK")
    #expect(update.grid == "OF88AA")
    #expect(update.band == "20m")
    #expect(update.countryBearing == 249)
    #expect(update.stationBearing == 251)
}

@Test func rumlogCountryRefreshKeepsStationCallsignAtSameBearing() throws {
    let update = try RUMlogRotatorParser.parse(Data("""
        <AppInfo><ShownDxcc>EA</ShownDxcc><HdgToDxcc>249</HdgToDxcc></AppInfo>
        """.utf8))
    #expect(update.callsign.isEmpty)
    #expect(update.countryCode == "EA")
    #expect(update.stableLabel(previous: "EA2ESU", previousBearing: 249, targetBearing: 249, fallback: "DXCC") == "EA2ESU")
    #expect(update.stableLabel(previous: "EA2ESU", previousBearing: 249, targetBearing: 210, fallback: "DXCC") == "EA")
}

@Test func rumlogRotorCommandAndJSONAreAccepted() throws {
    let command = try RUMlogRotatorParser.parse(Data("<Rotor><RotorCommand>93</RotorCommand></Rotor>".utf8))
    #expect(command.commandedBearing == 93)
    let json = try RUMlogRotatorParser.parse(Data(#"{"call":"ZL1ABC","grid":"RF73"}"#.utf8))
    #expect(json.callsign == "ZL1ABC")
    #expect(json.grid == "RF73")
}

@Test func importsExistingRotorPreferencesWithoutEnablingAutomaticMovement() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    let preferences = root.appendingPathComponent("Library/Containers/de.dl2rum.Rotor/Data/Library/Preferences")
    try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
    let rotor: [String: Any] = [
        "RotorType": "DCU-1", "RotorIdentifier": "ARCO", "tcpAddressAz": "rotator.local",
        "tcpPortAz": 4001, "PollRateIdx": "100 ms", "AutoConnect": true,
        "LogUdpPort": 12064, "UseLogDxccForAuto": true, "AutoRotate_6": true,
    ]
    let shared: [String: Any] = ["MyLocator": "JN88UQ"]
    try PropertyListSerialization.data(fromPropertyList: rotor, format: .binary, options: 0)
        .write(to: preferences.appendingPathComponent("de.dl2rum.Rotor_0.plist"))
    try PropertyListSerialization.data(fromPropertyList: shared, format: .binary, options: 0)
        .write(to: preferences.appendingPathComponent("de.dl2rum.Rotor.plist"))

    let imported = RotatorConfiguration.importedRotorConfiguration(homeDirectory: root.path)
    #expect(imported?.name == "ARCO")
    #expect(imported?.host == "rotator.local")
    #expect(imported?.homeGrid == "JN88UQ")
    #expect(imported?.enabledBands.contains("20m") == true)
    #expect(imported?.automaticTurningEnabled == false)
    try FileManager.default.removeItem(at: root)
}
