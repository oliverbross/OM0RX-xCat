# SmartLink implementation

OM0RX-xCat uses the established FlexRadio public-client password-realm flow
authorized for this project by its owner. The SmartLink password is transient:
it is used for the initial exchange, cleared from memory after authentication,
and never written to application settings or source control.

Refresh tokens are stored in macOS Keychain under an account-specific key based
on the normalized SmartLink email address. Changing email cannot silently reuse
another account's refresh token. Keychain items use
`WhenUnlockedThisDeviceOnly`; **Forget Saved Session** deletes the selected
account's token.

## Connection chain

1. Obtain or refresh the SmartLink token set.
2. Connect with normal system TLS verification to
   `smartlink.flexradio.com:443`.
3. Register the application, maintain broker pings, and request the selected
   radio. A configured serial is strict; no other account radio is substituted.
4. Retain the broker connection and obtain a fresh one-time WAN validation
   handle.
5. Connect to the radio's advertised TLS endpoint. Its self-signed certificate
   is trust-on-first-use pinned in Keychain by radio serial. Certificate changes
   are rejected until the operator uses **Reset Radio Certificate Pin**.
6. Send `wan validate`, require its successful sequence-correlated response,
   and wait for the radio handle before subscribing.
7. Subscribe to the client, slice, and radio objects supported by SmartSDR
   4.2.20, bind to the exact GUI station, and follow that station's slices.
8. Rebuild the entire broker/radio chain with a fresh handle after failure.

Commands have sequence-correlated acknowledgements and deadlines. A rejected
tune, mode, split, CW, or PTT command is reported as failure instead of being
treated as successful merely because the bytes reached the socket.

## Slice and VFO mapping

SmartSDR slice IDs are not VFO letters. OM0RX-xCat maps the configured station's
`index_letter` values to CAT VFO A/B and requires matching station ownership.
The active slice is reported as RX; the slice with `tx=1` is reported as TX.
These roles may be on the same or different slices. Each VFO retains its own
frequency and mode in the app status model.

An incremental new-slice event is considered live unless the radio explicitly
reports `in_use=0` or removes it. This is required because SmartSDR can omit
`in_use=1` when B is opened after the subscription is established.

## Current network boundary

v0.2.0 supports radios reachable through the broker-advertised public or UPnP
TLS/TCP port. UDP registration and NAT hole punching are not implemented, so
that topology remains unverified and is not claimed as supported.

Primary protocol references:

- [FlexRadio SmartLink API reference](https://www.flexradio.com/documentation/smartsdr-waveform-api-pdf/)
- [SmartSDR TCP/IP API](https://github.com/flexradio/smartsdr-api-docs/wiki/SmartSDR-TCPIP-API)
