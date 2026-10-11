# Remote Station Agent client

OM0RX-xCat 0.5.1 includes a connection mode for the independent Windows OM0RX
Remote Station Agent. The Windows process remains the sole owner of the
FLEX-8400, KPA500, and KAT500 hardware connections. The Windows agent is
source-deployed from
[WindowsAgent](../WindowsAgent/);
that repository is public. It is not bundled in the macOS xCat archive and no
standalone Windows `.exe` or MSI installer is currently published, so deploy it
from source using the supplied PowerShell scripts.

## Configure

1. Configure and start the Windows agent using its
[deployment guide](../WindowsAgent/docs/REMOTE_STATION_AGENT.md).
2. Publish only its loopback listener with Tailscale Serve. Do not enable
   Funnel or forward port 8840 on the public router.
3. In OM0RX-xCat select **Remote Station Agent**.
4. Enter the `https://...` Tailscale Serve base URL. URLs containing embedded
   credentials, query parameters, fragments, or a non-HTTPS scheme are rejected.
5. Paste the agent `server.control_token`, then choose **Save Settings**. The
   token is stored in macOS Keychain under an endpoint-specific account and is
   cleared from the UI.
6. Enable **Full CAT and station control** for normal operation. Start
   OM0RX-xCat and point RUMlogNG to `127.0.0.1:15002`.

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

The application also exposes RIT, XIT, and RF-policy-power controls.
Kenwood-compatible CAT `RT`, `XT`, and `PC` reads are supported. `XT` and `PC`
writes require the full-control opt-in, and the Windows agent remains the
authoritative hardware and station-policy endpoint.

After a successful CAT frequency request, xCat compares the requested VFO with
the authoritative WebSocket readback. If the first acknowledged request is not
observed within two seconds it is retried once. If the retry is still not
confirmed, xCat removes the temporary CAT value and reports the true FLEX
frequency rather than leaving RUMlog on a false QSY.

## Safety boundary

Remote Agent mode creates a `RemoteAgentClient` as the only `RadioControlling`
implementation. It never creates a parallel SmartLink client. All local CAT and
RigCtlD writes therefore translate to version-1 `POST /api/v1/commands`
envelopes with unique idempotency keys.

With full control enabled, xCat forwards every command advertised by the agent.
Commissioning, route, issue, and alarm state remains visible as operator
advisory information but does not create a second Mac-side policy latch. Basic
transport and command-capability validation still applies.

No bearer credential is logged or added to a URL. WebSocket authentication uses
the `Authorization: Bearer` header.
