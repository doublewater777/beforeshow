# Experiments

## Simulator verification

On an iPhone 17 simulator:

1. Open an uninvited companion shortcut.
2. Enter an optional name and open the system share sheet.
3. Verify pending state, resend, confirm, and cancel affordances.
4. Confirm the friend and verify the avatar shortcut.
5. Restart the app and verify the state remains confirmed.
6. End the show and verify the shortcut becomes Shared Footprint.

## Measurement

- Pass: every transition is reachable, persisted, accessible, and visually matches the prototype hierarchy.
- Pass: all iOS tests remain green.
- Loop back: any transition is lost after sharing/relaunch, or the local-confirmation copy is mistaken for remote delivery.

Release-user comprehension remains unmeasured until the feature is exercised outside the simulator.
