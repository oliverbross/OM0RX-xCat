# OM0RX-xCat

OM0RX-xCat is a native macOS bridge that presents loopback-only Kenwood CAT and
Hamlib RigCtlD TCP services backed by a FlexRadio. It is designed as a stable,
transparent replacement for the legacy xCAT utility used by RUMlogNG and
Flex-WavelogGate.

Copyright © 2026 Oliver Bross OM0RX. Licensed under GPL-3.0-only.

## Current development build

- Native Apple Silicon Swift/SwiftUI application for macOS 14 or later.
- Simulator mode for safe testing without touching a radio.
- Direct local-network SmartSDR TCP connection on port 4992.
- Follows a configured SmartSDR GUI station and slice using `client bind`.
- RUMlogNG TS-480-compatible polling: `FA`, `FB`, `KS`, `AI`, `IF`, `FR`, `FT`,
  `MD`, `RX`, opt-in `TX`, and bounded `KY` CW commands.
- RigCtlD compatibility used by Flex-WavelogGate: `f`, `m`, `F`, and `M`.
- Exponential reconnect, heartbeat, generation-safe callbacks, bounded command
  buffers, and forced unkey/CW clear when a CAT client disconnects.
- Both services bind to `127.0.0.1` only.

SmartLink is not enabled in this development build. FlexRadio provisions a
unique OAuth client ID and registered redirect URI for each public app. The app
will use Authorization Code + PKCE once FlexRadio issues those credentials;
credentials or tokens from another application will not be copied or reused.

## Build and test

```sh
swift test
./scripts/package-app.sh
open dist/OM0RX-xCat.app
```

The packaging script requires a valid `Developer ID Application` certificate
and produces `dist/OM0RX-xCat.app` with hardened-runtime signing.

## Safe RUMlogNG test

The first launch uses Simulator mode and alternate ports to avoid the existing
xCAT process:

- CAT: `127.0.0.1:15002`
- RigCtlD: `127.0.0.1:14532`

In RUMlogNG, select Kenwood TS-480 and TCP, then temporarily use port 15002.
Confirm frequency and CW-speed polling before trying writes. Leave **Allow CAT
transmit and CW commands** off for receive-only validation. Only after stopping
the original xCAT should the ports be changed to CAT 5002 and RigCtlD 4532.

For a local-network radio, select **Local network**, enter the radio IP or host,
the exact SmartSDR station name (for example `Maestro`), and the slice letter.

## Safety

CAT transmit is disabled by default. `RX` remains available even when transmit
commands are disabled. Test PTT only under operator supervision at low power or
into a dummy load. This software does not carry or supervise RF audio.

## Project status

This is an initial test build, not yet a notarized public release. Split-slice
lifecycle and SmartLink end-to-end operation need hardware/account acceptance
before the first stable release.
