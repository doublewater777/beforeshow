# Use AMap provider for departure options

BeforeShow will introduce a departure route provider boundary for searching transport options and opening navigation, while keeping saved departure plans and home reminders inside the app domain. The first default provider will use AMap route planning and URI navigation because the product's initial concert and livehouse scenarios are China-centered and need detailed driving, public transport, and taxi-friendly options; Apple MapKit can remain a future fallback behind the same provider boundary.

Route facts must come from the map provider. AI or local formatting may summarize provider results in BeforeShow's tone, but must not invent transport options when the provider has no route result.

The UI should expose a single map action, such as "Open Map", rather than asking users to choose a map app. The provider is responsible for opening AMap when available and falling back to web or system maps when needed.
