---
name: life360-location-awareness
title: Life360 Location‑Awareness Helper
description: Auto‑detects which family member to query for location‑aware questions; defaults to Rob when no name is given.
summary: |
  Auto‑detects which family member to query when a user asks a location‑sensitive question.
  • No‑name → defaults to the member specified in the configuration file `default_member.txt` (e.g., **Rob**).
  • Named‑member → fetches that member's location.
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

```python
def handle(query: str) -> dict:
    """Detect intent, get member location via MCP, then search the web for nearby places.
    Returns a dict that the assistant can render directly."""
    # --- intent detection -------------------------------------------------
    activity, kw = _detect_activity(query)
    if activity is None:
        return {"status": "need_clarification", "message": "I'm not sure what you'd like to do. Do you want to eat, go outside, see a movie, etc.?"}
    # --- resolve member ----------------------------------------------------
    member = _resolve_target_member(query)
    # --- ask the MCP for fresh GPS ---------------------------------------
    loc = tool_call("get_location", {"member": member, "force_fresh": True})
    if "error" in loc:
        return {"status": "error", "message": f"Could not get {member}'s location: {loc['error']}"}
    lat, lon = loc["latitude"], loc["longitude"]
    # --- web‑search for nearby venues ------------------------------------
    suggestions = _search_nearby(lat, lon, kw)
    suggestion_lines = "\n".join(f"- [{s['title']}]({s['url']})" for s in suggestions) or "No results found."
    answer = f"Based on **{member}**'s current location (≈{lat:.4f}, {lon:.4f}) I found the following {activity} options:\n{suggestion_lines}"
    return {"status": "ok", "answer_text": answer, "member": member, "activity": activity, "location": {"lat": lat, "lon": lon}, "suggestions": suggestions}
```
- **User:** "Where's a good place to eat now?"
  **Assistant:** (runs steps, defaults to Rob, then suggests nearby restaurants).
- **User:** "Is it safe for Deb to play outside?"
  **Assistant:** (runs steps with `target = "Deb"`, then answers using Deb's coordinates).