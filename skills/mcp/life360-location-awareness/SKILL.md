---
name: life360-location-awareness
title: Life360 Location‑Awareness Helper
description: Auto‑detects which family member to query for location‑aware questions; defaults to Rob when no name is given.
summary: |
  Auto‑detects which family member to query when a user asks a location‑sensitive question.
  • No‑name → defaults to the member specified in the configuration file `default_member.txt` (e.g., **Rob**).
  • Named‑member → fetches that member’s location.
  • No extra preferences – uses the freshest GPS reading.
---

## Procedure

1. **Resolve target member**
   - Scan the user request for a first‑name that matches any of the known Life360 members (Rob, Deb, Edward, Ethan).
   - If a name is found, set `target = <name>`.
   - If none is found, set `target = "Rob"`.

2. **Call Life360 MCP**
   ```python
   location = mcp_life360_get_location(member=target)
   ```
   The call returns a JSON object containing:
   - `latitude`
   - `longitude`
   - `accuracy`
   - `battery`
   - `timestamp`
   - `cached` (boolean indicating whether the reading may be stale).

3. **Add context to the answer**
   - Append a short note to the final response, e.g.
     "(based on the latest location for **{target}**: {latitude}, {longitude})".
   - If the answer requires distance calculations or nearest‑venue lookup, use the coordinates from `location`.

## Pitfalls & Tips
- The MCP server might return a cached reading; check the `cached` flag. If freshness is critical, re‑query after a short delay (≈5 s).
- If multiple members share the same first name (unlikely here), ask the user for clarification.

## Examples
- **User:** "Where’s a good place to eat now?"
  **Assistant:** (runs steps, defaults to Rob, then suggests nearby restaurants).
- **User:** "Is it safe for Deb to play outside?"
  **Assistant:** (runs steps with `target = "Deb"`, then answers using Deb’s coordinates).
