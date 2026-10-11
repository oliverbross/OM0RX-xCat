# Windows Codex handoff: move the Windows agent into OM0RX-xCat

Use this handoff after the current Windows task is finished. The objective is
to make OM0RX-xCat the single owning GitHub project for both the macOS client
and its Windows Remote Station Agent.

## Repositories

- Destination: <https://github.com/oliverbross/OM0RX-xCat>
- Current source: <https://github.com/oliverbross/om0rx-radio-control>
- Owner and author: Oliver Bross, OM0RX
- License: GPL-3.0-only

Both repositories are public. Fetch both and record the exact source and
destination commit SHAs before changing anything. Work on a new
`codex/windows-agent-migration` branch in `OM0RX-xCat`. Preserve unrelated work
and never copy local configuration, credentials, tokens, logs, or station
secrets.

## Required result

Move the complete, independently deployable Windows Remote Station Agent into
the `OM0RX-xCat` repository. The destination must contain everything needed to
install, configure, test, run, and maintain the Windows agent without cloning
`om0rx-radio-control`.

Use a clear destination such as `WindowsAgent/` and make it a self-contained
Python project. Preserve the existing `python -m remote_station` command if
practical so installed stations do not require an unnecessary command change.
All PowerShell launchers must resolve paths relative to their own installed
location rather than depending on the caller's working directory.

## Source inventory

Start with, but do not assume this is the complete dependency graph:

- `remote_station/**`
- `scripts/remote_agent/**`
- `requirements-remote-agent.txt`
- `docs/REMOTE_STATION_AGENT.md`
- `docs/REMOTE_STATION_PROTOCOL_V1.md`
- `tests/smoke/test_remote_station_agent.py`
- `tests/smoke/test_remote_station_tray_contract.py`

The agent currently imports station-control code from
`radio_control.elecraft`, `radio_control.flex_radio`, and
`services.elecraft_station`. Trace every transitive import, runtime asset,
PowerShell dependency, startup shortcut, scheduled-task assumption, and test
fixture. Move or refactor the smallest coherent agent-owned implementation;
do not copy the entire radio-control application into xCat. Shared modules
still required by the old application may remain there, but the migrated agent
must not import from or require the old repository at runtime.

Review the path history for the agent before moving it. Preserve authorship and
provenance in commit messages and `NOTICE`; use a history-preserving migration
method where it is safe and practical. Do not rewrite either public
repository's existing history.

## Destination layout and packaging

Create a self-contained Windows-agent area with:

- its Python package and explicit Python 3.11+ metadata;
- a minimal locked or constrained dependency definition;
- PowerShell setup, configuration, run, tray/widget, startup install/uninstall,
  and Tailscale Serve scripts;
- focused unit/contract tests and Windows CI;
- the protocol and Windows deployment documentation;
- an example configuration containing placeholders only;
- `.gitignore` coverage for environments, caches, logs, generated settings,
  tokens, and build artifacts.

Do not bundle the agent inside the macOS ZIP. The xCat repository and release
notes must clearly distinguish the macOS application artifact from the Windows
agent source. If no signed Windows `.exe` or MSI is produced by this task, say
so plainly. Do not claim signing, packaging, live RF validation, or a published
Windows binary without evidence.

## Documentation changes

Update the OM0RX-xCat README and relevant docs so that:

1. all Windows source, clone, setup, and deployment links point to
   `oliverbross/OM0RX-xCat`;
2. commands start from the new Windows-agent directory and work exactly as
   written in a fresh clone;
3. the macOS client setup explains how it connects to the Windows agent over
   authenticated HTTPS/WebSocket through private Tailscale Serve;
4. the bearer token remains in macOS Keychain and never appears in URLs, logs,
   screenshots, examples, or committed configuration;
5. the Windows agent is identified as the sole owner of the FLEX and
   KPA500/KAT500 control connections;
6. no product documentation discusses or advertises software that is not
   bundled with this project;
7. owner/author attribution remains Oliver Bross OM0RX and licensing remains
   GPL-3.0-only.

After the destination is verified, update the old repository's README and
agent documentation with a short relocation notice and canonical xCat link.
Remove the dedicated `remote_station` package, agent PowerShell scripts,
agent-only requirement file, migrated tests, and duplicate protocol/deployment
documents from the old repository only after confirming nothing remaining
imports them. Do not delete shared radio-control modules or unrelated software.

## Compatibility and safety requirements

- Preserve the version-1 authenticated HTTP/WebSocket protocol used by the
  Swift `RemoteAgentClient` unless both sides and their tests are updated in
  the same change.
- Keep the agent listener loopback-only by default. Use private Tailscale Serve;
  never enable Funnel or require public router forwarding.
- Preserve command idempotency, bounded input, redacted state/config output,
  sanitized logging, receive recovery, commissioning gates, route validation,
  and all FLEX/Elecraft interlocks.
- Preserve exclusive station-controller ownership and single-instance
  behavior. The tray and widget are control surfaces, not additional hardware
  controllers.
- Do not weaken transmit, tuning, amplifier, antenna, or route safeguards to
  make tests pass.
- Never perform an unsupervised RF, PTT-on, TUNE, CWX, or amplifier-operate
  test. Keep the amplifier in standby for receive-only acceptance.

## Required verification

From a fresh clone of `OM0RX-xCat`, prove on Windows that the documented
commands can:

1. create an isolated Python environment and install only the agent
   dependencies;
2. create and validate a credential-free initial configuration;
3. run `python -m remote_station check` successfully with safe test settings;
4. start the loopback service and pass authenticated health/state checks;
5. install and remove the controller and tray startup tasks idempotently;
6. launch the tray, settings window, and station widget without a visible
   PowerShell console or duplicate controller;
7. run all migrated Python and PowerShell contract tests;
8. run the macOS `swift test` suite or leave it demonstrably unchanged if the
   Windows host cannot run Swift;
9. pass Ruff `F,E9`, Python compilation, Git whitespace checks, and a secret
   scan of the migrated files;
10. confirm the old repository has no remaining runtime or documentation link
    required by the migrated agent.

Perform receive-only live checks only when the station is available and Oliver
has authorized the necessary lifecycle actions. Keep offline tests, live
Windows validation, physical-radio validation, code signing, and release
publication as separate evidence.

## Delivery

- Commit the destination migration on `codex/windows-agent-migration` and push
  it to `oliverbross/OM0RX-xCat`.
- Commit old-repository cleanup separately, only after destination acceptance,
  so it can be reviewed or reverted independently.
- Once the current Windows task is complete, remove the superseded
  `docs/WINDOWS_CODEX_EXCLUSIVE_CONTROLLER_HANDOFF_2026-10-11.md` from the old
  repository as part of that cleanup.
- Open or provide review links for both changes and report exact branch names,
  commit SHAs, test commands, pass/fail counts, and any unverified boundaries.
- Do not publish a release or merge either branch unless Oliver explicitly asks
  for that final action.

