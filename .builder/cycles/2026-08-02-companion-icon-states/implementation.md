# Implementation

- Persist an optional companion name and four-state lifecycle on each `Show`.
- Replace the one-tap share shortcut with a prototype-faithful drawer.
- Render a pending indicator, confirmed avatar stack, canceled retry label, and ended shared-footprint label in the existing quick-action tile.
- Save state before presenting the system share sheet so the share controller cannot steal the state transition.
- Derive shared history from confirmed, ended shows with the same companion name.
- Add focused lifecycle, presentation, and persistence tests.

The implementation intentionally uses a manual local confirmation action. No account, invitation token, remote callback, or new permission is introduced.
