# Assumptions

- A start time must be explicit because countdown and notification behavior depend on it.
- Users understand a prefilled draft when missing fields remain visibly incomplete.
- Requesting notification permission immediately after the first successful save is contextual enough to be trusted.
- Preventing duplicate writes and misleading errors matters more than keeping the current in-sheet success pause.

Riskiest assumption: moving success feedback to the destination surface while the notification permission prompt may appear still feels like one coherent completion.

Falsifier: simulator QA shows users can save without confirming a time, receive duplicate shows, lose parsed fields, or see the success state before returning home.
