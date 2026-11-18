# Prefer ranked artist search results with portraits

Status: Accepted

## Context

Strict name equality and exhaustive searches of simplified, traditional and bilingual credits reject useful catalog matches. Locally promoting exact names can select a different artist: a search for 回春丹乐队 may rank 回春丹 first even when an exact-name artist also exists.

## Decision

- Search each unresolved artist's original credit once. Do not generate additional remote searches for spelling or bilingual variants.
- Exclude search candidates without an avatar URL, deduplicate by Artist ID, and preserve MusicKit's original artist ordering. An avatar URL is catalog metadata; image downloading is not a prerequisite for matching.
- Automatic matching adopts the preferred eligible result without requiring the input and catalog display names to match. If that result's name also belongs to another eligible Artist ID, leave it for manual selection.
- Do not strip suffixes such as 乐队 or maintain an alias dictionary to guess identity. Catalog ranking supplies alias and spelling handling.
- Existing confirmed identities and explicit Apple Music links retain priority. This change does not delete or relink saved artists.
- Retain local name normalization and bilingual spelling comparison for reusing known lineup identities. These comparisons do not issue additional remote requests.
- While a user is typing in a timetable form, show candidates in the same order. Automatically fill only when the preferred result fully equals the normalized entered name; never promote a lower-ranked exact-name result or replace an unfinished prefix with an unrelated credit. The user may select any offered candidate.
- MusicKit remains the authorized source; iTunes remains available only without music access for matching, and for existing other uses. The old iTunes song-inference path is removed because it can produce only avatarless candidates, which are no longer eligible. MusicKit song relationships still recover artists with portraits. No cloud token service is added.

## Consequences

Catalog ranking may choose an unintended artist. Users can rematch in Listen or timetable editing; avoiding unnecessary manual work is preferred over rejecting every alias or spelling difference. Same-name conflicts remain explicit choices. No persistent field, ID format, UserDefaults key, deep link or widget kind changes.
