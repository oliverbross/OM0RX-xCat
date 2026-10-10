# Repository Guidelines

## Scope

OM0RX-xCat is a macOS-only Swift package. Keep the CAT and RigCtlD servers
loopback-only and keep CAT transmit opt-in. The owner has explicitly authorized
the established FlexRadio public-client password-realm flow used here. Never
persist or log the user's password, and keep refresh tokens account-scoped in
macOS Keychain.

## Layout

- `Sources/XCatCore`: protocol processors, loopback TCP server, radio clients.
- `Sources/OM0RXXCatApp`: SwiftUI application and lifecycle.
- `Tests/XCatCoreTests`: deterministic protocol compatibility tests.
- `Resources`: application metadata and signing entitlements.
- `scripts/package-app.sh`: release build and Developer ID packaging.

## Commands

- `swift test` builds all targets and runs the test suite.
- `./scripts/package-app.sh` creates the exact signed app in `dist/`.
- `codesign --verify --deep --strict dist/OM0RX-xCat.app` verifies signing.

## Conventions

Use Swift concurrency for shared state and `Network.framework` for sockets.
Handle fragmented and coalesced TCP input, bound all buffers, and keep protocol
responses deterministic. Preserve the observed RUMlogNG TS-480 poll contract
and Flex-WavelogGate RigCtlD contract with tests. A connection loss must attempt
to unkey and clear CW state.

The legacy xCAT relay is a fallback transport. Keep its upstream socket
independent from the downstream listeners and preserve automatic reconnect plus
process supervision.

## Validation

Use alternate ports 15002/14532 while legacy xCAT owns 5002/4532. Unit tests,
the packaged app, signing, live listeners, RUMlogNG, a real radio, SmartLink,
and notarization are separate evidence; report each accurately. RF transmit
testing requires a supervised operator and safe radio setup.

## Licensing

New source is GPL-3.0-only, copyright Oliver Bross OM0RX. Retain attribution in
`NOTICE` when adapting code from Oliver's other projects.
