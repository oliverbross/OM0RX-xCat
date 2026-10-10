# Mac rotator control

OM0RX-xCat 0.5 controls the antenna rotator directly from the Mac. The rotator
path is independent from the Windows Remote Station Agent and does not change
radio, KPA500, KAT500, route, or Windows station configuration.

## Current controller

The first implementation supports the station's existing DCU-1 TCP path. On
first launch it can import these non-secret settings from the installed Rotor
application:

- rotor name and DCU-1 protocol
- TCP host and port
- polling rate and connect-at-launch preference
- home Maidenhead grid
- RUMlog logbook UDP port
- enabled bands, per-band offsets, and bidirectional antenna choices
- the path to Rotor's `grids.txt` callsign database

Automatic turning is deliberately left off during migration. Enable it in the
Rotator tab after verifying the live azimuth and target. Manual Turn, clockwise,
counter-clockwise, and Stop controls remain available whenever the controller is
connected.

The DCU-1 commands used are:

- `AI1;` — poll azimuth
- `AP1xxx;AM1;` — set and start a target bearing
- `U` / `D` — clockwise / counter-clockwise manual motion
- `;` — stop

## RUMlogNG

The imported station configuration listens on UDP 12064. Quit the separate
Rotor application before connecting OM0RX-xCat because only one application
should own the rotator connection and RUMlog UDP listener.

RUMlog remains the best source for active-station and DXCC direction because it
already knows the selected callsign and, when available, the station grid. A
click on RUMlog's rotor needle is treated as an explicit turn request. Automatic
turning uses the configured DXCC or Station source and only the selected bands.
The controller applies a one-degree physical deadband even when the configured
minimum change is zero. This prevents repeated RUMlog updates for the same
callsign from commanding an already-settled rotor without delaying a real
target change.
RUMlog can follow a station update with a country-only refresh. OM0RX-xCat
retains the station callsign when that refresh has the same target bearing, so
the monitor does not collapse a selected call such as `EA2ESU` to `EA`.

If RUMlog resolves a callsign but OM0RX-xCat remains on the previous target,
open RUMlog **Settings > UDP** and cycle **App info (N1MM, RUMlog)** off and on.
This restarts RUMlog's UDP broadcaster without changing the configured
`127.0.0.1:12064` destination. The Rotator tab confirms recovery by replacing
`Listening on 127.0.0.1:12064` with the received callsign and bearing.

## Bearing accuracy

The home position uses the centre of the configured 4, 6, 8, or 10-character
Maidenhead locator. An exact station grid produces a WGS-84 great-circle initial
bearing and distance. A callsign entered manually is resolved through the
configured `call,grid` database. RUMlog's DXCC bearing is used when no exact
station grid is available.

`cty.dat` is useful for DXCC/prefix classification, but a country centroid is not
an exact station position. It is therefore not used in preference to a station
grid or RUMlog's own resolved bearing.

## Monitor

The station monitor is widened into two independent panes:

- radio, VFO, KPA500, KAT500, route, and station actions on the left
- rotator status, live compass, target-area map, and movement controls on the
  right

The detached monitor remains a normal movable macOS window and restores its
screen position. The compass has one full needle: the cyan physical-antenna
readback. It smoothly interpolates the 100 ms samples by the shortest path across
0°/360°, while the current numeric heading and CW/CCW state continue to follow
the controller readback. The selected target stays outside the compass as a
separate numeric bearing and map marker, so it cannot be mistaken for a second
antenna.

Click anywhere inside the compass to set that bearing and send a DCU-1 turn
command. The map follows each geographic target and zooms to its country or
region; it falls back to a world view when no target coordinate is available.
The map target is exact when a grid is known. When RUMlog only supplies a bearing,
the projected map point is directional context and the compass remains
authoritative.
