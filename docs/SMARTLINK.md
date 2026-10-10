# SmartLink implementation boundary

OM0RX-xCat will use FlexRadio's current public-app authentication path:
Authorization Code with PKCE in `ASWebAuthenticationSession`, a unique client
ID, and a registered redirect URI. It will not extract or reuse the legacy
xCAT/xLib client ID, passwords, refresh tokens, or Auth0 sessions.

## Credential request

Send this request to the FlexRadio developer program:

> Please provision a native/public OAuth client for OM0RX-xCat using
> Authorization Code with PKCE and register our macOS callback URI. Please
> confirm which issued token SmartLink expects in `application register` and
> the current SmartLink API redistribution terms.

## Planned connection chain

1. Authenticate with PKCE and retain only the refresh token in Keychain.
2. Connect with normal TLS verification to `smartlink.flexradio.com:443`.
3. Register the application, maintain a ten-second broker ping, and obtain a
   fresh one-time WAN handle for the selected radio.
4. Connect to the radio's advertised TLS endpoint and validate the handle.
5. Use certificate fingerprint approval/pinning for the radio's self-signed
   WAN certificate; never use trust-all TLS.
6. Register a UDP socket, subscribe to TCP state, resolve the chosen GUI
   station and slice locally, and expose it through CAT/RigCtlD.

The SmartLink server connection and radio connection are one generation-safe
session. Losing either invalidates the radio list, WAN handle, and cached slice
state. Reconnection must build the chain again and never silently choose a
different station or slice.

Public-port or UPnP endpoints will be supported first. NAT hole punching needs
a controlled live test because the public documentation does not fully specify
that exchange.

Primary references:

- FlexRadio Developer Program: https://www.flexradio.com/api/developer-program/
- SmartSDR TCP/IP API: https://github.com/flexradio/smartsdr-api-docs/wiki/SmartSDR-TCPIP-API
