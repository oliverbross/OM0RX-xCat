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
- rotator status, live compass, beam sector, target, world map, and movement
  controls on the right

The detached monitor remains a normal movable macOS window and restores its
screen position. The map target is exact when a grid is known. When RUMlog only
supplies a bearing, the map shows a clearly bounded bearing projection while the
compass remains authoritative.
