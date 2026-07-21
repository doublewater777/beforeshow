# Setlist Reliability Verification Assumptions

- Users value preserving an existing complete list more than seeing unvalidated provider items early.
- A clean transport close is not proof that generation completed; only an explicit validated final snapshot is sufficient.
- Cancelling a lineup sheet must leave persisted artist interests untouched.
- The existing drag affordance is understandable when paired with accessibility move actions.

Riskiest assumption: delaying visible song rows until the provider response validates will still feel responsive enough with the existing generation status copy.

Falsification: users abandon generation while status text is visible or report that generation appears stuck.
