# Remove Setlist Guess

Stage: business-model

Target user: a live-music attendee using BeforeShow to track one current show and understand when it starts.

User problem: the setlist-guess feature adds a large speculative workflow that distracts from the product's clearer countdown and current-show focus.

Desired behavior change: users should land on a simpler current-show experience without seeing, generating, editing, sharing, or being notified about speculative setlists.

Success:

- No setlist-guess entry or copy remains in the iOS app.
- The iOS app builds and launches on the iPhone 17 simulator.
- Removing the feature also removes its local models, generation flow, Pro gate, notification destination, and permissions.

Out of scope:

- Redesigning the countdown card.
- Replacing setlist guess with a new feature.
- Migrating pre-release candidate-song data.
