# enka Roadmap

`enka` is a small macOS input source switcher for left/right Command key single-taps.

The product is intentionally not a general command launcher. Configured taps point directly at input source IDs, and the daemon keeps the key-event hot path as short as possible.

## Product Principles

- **Focused:** switch macOS input sources, avoid general launcher behavior.
- **Fast:** resolve input sources at startup; select cached sources on Command release.
- **Inspectable:** setup, status, and release scripts should show exactly what they touch.
- **Reversible:** uninstall and reset paths should remove only owned `enka` artifacts.
- **Respectful of macOS permissions:** use an app bundle identity and standard Accessibility prompts.

## Current Direction

- Rename the tool from `lrcmd` to `enka`.
- Ship one CLI binary, `enka`, plus `Enka.app` for Accessibility identity.
- Remove the separate `inctl` helper binary by folding input source operations into `enka sources/current/select`.
- Replace command-based config with first-class input source config:

```json
{
  "leftTap": {
    "source": "com.apple.keylayout.ABC"
  },
  "rightTap": {
    "source": "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
  }
}
```

## Owned Artifacts

- Install root: `~/Applications/enka`
- CLI: `~/Applications/enka/bin/enka`
- App bundle: `~/Applications/enka/Enka.app`
- LaunchAgent: `~/Library/LaunchAgents/dev.ultrahope.enka.plist`
- Config: `~/.config/enka/config.json`
- State/log directory: `~/.local/state/enka`
- Release archive: `enka-v<version>-<platform>.tar.gz`

## Near-Term Backlog

- Finish the `enka` breaking rename across Swift code, scripts, docs, and release verification.
- Verify `enka sources/current/select` on a real macOS session.
- Verify setup dry-run does not create config or LaunchAgent directories.
- Verify release packaging contains only `bin/enka`, `Enka.app`, README, and optional LICENSE.
- Document Background Activity behavior if reboot/startup issues reappear.
