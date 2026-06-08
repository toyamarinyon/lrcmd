# enka Roadmap

`enka` is a small macOS input source switcher for left/right Command key single-taps.

The product is intentionally not a general command launcher. The daemon keeps the key-event hot path as short as possible and posts the dedicated JIS input toggle keys directly.

## Product Principles

- **Focused:** switch macOS input sources, avoid general launcher behavior.
- **Fast:** keep the tap path minimal; post the toggle key directly on Command release.
- **Inspectable:** install, status, and release scripts should show exactly what they touch.
- **Reversible:** uninstall and reset paths should remove only owned `enka` artifacts.
- **Respectful of macOS permissions:** use an app bundle identity and standard Accessibility prompts.

## Current Direction

- Rename the tool from `lrcmd` to `enka`.
- Ship one CLI binary, `enka`, plus `Enka.app` for Accessibility identity.
- Do not expose tap source configuration; the daemon posts fixed JIS Eisuu/Kana keycodes directly.

## Owned Artifacts

- Install root: `~/Applications/enka`
- CLI: `~/Applications/enka/bin/enka`
- App bundle: `~/Applications/enka/Enka.app`
- LaunchAgent: `~/Library/LaunchAgents/dev.ultrahope.enka.plist`
- State/log directory: `~/.local/state/enka`
- Release archive: `enka-v<version>-<platform>.tar.gz`

## Near-Term Backlog

- Finish the `enka` breaking rename across Swift code, scripts, docs, and release verification.
- Verify install with temporary install, LaunchAgent, and state directories.
- Verify release packaging contains only `bin/enka`, `Enka.app`, README, and optional LICENSE.
- Document Background Activity behavior if reboot/startup issues reappear.
