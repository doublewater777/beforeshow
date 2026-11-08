# Match companion history by name

BeforeShow still has no stable cross-show companion identity. Names are trimmed, de-duplicated lists stored on each show (`Show.companionNames`).

There is one count (ADR 0048): each named person is counted wherever that name appears on a footprint, whoever else came. The companion sheet, per-person history and footprint detail all use it.

Renamed companions stop matching, and different people with the same name can collide. That is accepted until a stable companion ID exists.
