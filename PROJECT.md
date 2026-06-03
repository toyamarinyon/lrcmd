# lrcmd Roadmap

lrcmd is a small, inspectable macOS utility that maps left/right Command taps to input sources.  
The current direction is to keep setup and service lifecycle predictable while staying respectful of macOS permission and privacy boundaries.

## Product principles

- **Small:** minimal binary surface and clear shell commands.
- **Inspectable:** every setup action should be understandable from logs and status output.
- **Reversible:** uninstall and reset paths should remove only owned artifacts.
- **Respectful of macOS permissions:** use app identities and standard prompts; avoid undocumented bypasses.

## Implemented

- Installer and onboarding defaults
  - Hosted installer script exists and is ready for the hosted install flow; endpoint deployment is still pending.
  - Install flow delivers `Lrcmd.app`, `lrcmd`, and `inctl` under the user install layout.
  - Setup onboarding path is in place after install.

- Accessibility flow via `Lrcmd.app`
  - `Lrcmd.app` is used as the macOS accessibility target instead of the CLI binary.
  - Setup opens `Lrcmd.app` and requests permission for that app identity.
  - Permission messaging now points users to app-centric approval in System Settings.

- LaunchAgent lifecycle
  - Setup can generate/update the LaunchAgent plist.
  - Setup and `lrcmd restart` manage agent lifecycle; `lrcmd status` reports state.
  - Restart path is wired for post-setup recovery and repeated onboarding.

- Release and packaging
  - Release archive packaging includes `Lrcmd.app`, `bin/lrcmd`, and `bin/inctl`.
  - Release packages include release metadata and installation artifacts used by onboarding and restart flows.
  - Dist output paths and packaging expectations have been aligned.

- Logging and operational visibility
  - Setup logs explicit actions for what was written/started.
  - Setup artifacts are written under `~/.config/lrcmd`; setup log output is written to `~/.local/state/lrcmd/setup.log`.
  - Distribution now treats `dist/` as generated and ignored in git.

- Follow-up knowledge captured from incident handling
  - Background Activity/Background mode can block auto-start after reboot; this must be captured as a diagnosed prerequisite in docs/flow.

## Remaining / Next

- Clarify diagnostic guidance for boot-time behavior:
  - Document why `lrcmd` may not auto-run on reboot until background activity is enabled.
  - Add explicit check steps in docs and status output to verify this condition.

- Permission status accuracy
  - Update `status` / `doctor` to check Accessibility for `Lrcmd.app` via LaunchServices, not CLI process identity.
  - Ensure mismatch scenarios report "app not yet approved" instead of "agent/CLI issue."

- Finish onboarding polish
  - Make setup output consistently show:
    - app path used for permission
    - plist path
    - service target and last start state
  - Keep dry-run-like behavior for tests/dev flows where prompts or service writes should be avoided.

- Maintain roadmap focus
  - Keep this file as a short backlog, not a speculative long-range vision.
  - Remove stale future work that is now implemented.

## User-facing check list (current)

- Install with hosted script
- Run `lrcmd setup`
- Open/approve `Lrcmd.app` for Accessibility
- Verify with `lrcmd status` or `lrcmd doctor`
- Use `lrcmd restart` if reboot/start behavior changes (especially around background activity)

## Near-term backlog priority

- High
  - Background Activity requirement documentation.
  - LaunchServices-based `status`/`doctor` permission check.
  - Restart behavior and startup diagnostics when app is not enabled.

- Medium
  - Keep status output stable for debugging and support threads.
  - Tighten release notes around `dist/` and reinstall behavior.

- Low
  - Minor onboarding wording refinements.
  - Optional command examples for common recovery paths.

## Tracking discipline

- Keep scope updates in `PROJECT.md` only when behavior changes.
- Remove old "to-do" entries once shipped.
- Prefer small, reviewable slices over large spec additions.
