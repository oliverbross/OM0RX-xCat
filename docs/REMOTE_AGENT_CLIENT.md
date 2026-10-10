# Remote Station Agent client

OM0RX-xCat 0.3 adds a connection mode for the independent Windows OM0RX Remote
Station Agent. The Windows process remains the sole owner of the FLEX-8400,
KPA500, and KAT500 hardware connections.

## Configure

1. Configure and start the Windows agent using the instructions in the
   `om0rx-radio-control` project.
2. Publish only its loopback listener with Tailscale Serve. Do not enable
   Funnel or forward port 8840 on the public router.
3. In OM0RX-xCat select **Remote Station Agent**.
4. Enter the `https://...` Tailscale Serve base URL. URLs containing embedded
   credentials, query parameters, fragments, or a non-HTTPS scheme are rejected.
5. Paste the agent `server.control_token`, then choose **Save Settings**. The
   token is stored in macOS Keychain under an endpoint-specific account and is
   cleared from the UI.
6. Keep **Allow CAT transmit and CW commands** off during receive-only
   commissioning. Start OM0RX-xCat and point RUMlogNG to `127.0.0.1:15002`.

Use **Forget Saved Agent Token** to remove the Keychain credential.

## State and controls

The client obtains the initial authoritative state with `GET /api/v1/state`,
then follows `WS /api/v1/stream`. A missing heartbeat forces a disconnect and
an exponential reconnect with a fresh HTTP state fetch.

The main two-line VFO display keeps VFO A first and VFO B second. In agent mode
the lines also include compact KPA/KAT, route, and alarm summaries. The menu-bar
widget provides the same status, safety inhibitors, and only those station
standby, operate, tune, or cancel buttons currently present in
`station.allowed_actions`.

The application also exposes guarded RIT, XIT, and RF-policy-power controls.
Kenwood-compatible CAT `RT`, `XT`, and `PC` reads are supported. `XT` and `PC`
writes require the CAT transmit opt-in, and the Windows agent independently
enforces commissioning and exact station policy.

## Safety boundary

Remote Agent mode creates a `RemoteAgentClient` as the only `RadioControlling`
implementation. It never creates a parallel SmartLink client. All local CAT and
RigCtlD writes therefore translate to version-1 `POST /api/v1/commands`
envelopes with unique idempotency keys.

Hazardous writes are rejected locally when authoritative state is stale,
unknown, unbound, uncommissioned, blocked, or alarmed, and remain subject to the
agent's own coordinator. Recovery operations—PTT off, CW clear, standby, and
cancel—are intentionally not hidden behind the hazardous-write latch.

No bearer credential is logged or added to a URL. WebSocket authentication uses
the `Authorization: Bearer` header.
