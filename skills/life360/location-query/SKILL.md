---
name: location-query
title: Location Query Wrapper
description: >-
  Ensures that any user request about family member locations or whereabouts is answered using the Life360 `l360` CLI tool. It abstracts common queries (find a person, list members, get coordinates) and delegates to the l360 CLI.
version: 1.0
---

## Purpose
When the user asks about location or whereabouts (e.g., "Where is Rob?" or "Who is at home?"), this skill defines the procedure to answer using the `l360` command rather than ad-hoc handling.

## Procedure
1. **Interpret the request** – Determine which operation the user wants:
   - *Locate*: get current location for a specific person
   - *List*: list all family members
   - *Circle*: view circle/circle members
2. **Invoke the appropriate `l360` command** based on the operation:
   - **Locate**
     - `l360 member locate <name>` – get location for a person
     - `l360 member locate Rob` – find Rob's current location
   - **List**
     - `l360 member list` – list all members in all circles
     - `l360 member list "Family"` – list members in specific circle
   - **Circle**
     - `l360 circle list` – list all circles
     - `l360 circle view` – view default circle
3. **Capture the FULL raw output** from l360 command (includes all details like battery, coordinates, last seen, etc.)
4. **Geocode the location** (IMPORTANT):
   - Use a geocoding service to convert lat/long to a readable place name
   - Try the `geocode` tool or `nominatim` tool if available
   - If no geocoder available, use a simple reverse geocode lookup:
     - Query OpenStreetMap Nominatim: `https://nominatim.openstreetmap.org/reverse?format=json&lat=<LAT>&lon=<LON>`
   - Extract `display_name` from the response for a human-readable address
5. **Return the SUMMARY response first**, then ask if the user wants more details:
   - **Summary format**: "{Name} is at {Place Name}. Address: {Full geocoded address}"
   - **Prompt**: "Would you like more details (battery, coordinates, last seen)?"
6. **Only if user confirms** they want more details, present the full l360 output.

## Edge Cases
- If the member name is not found, suggest nearby matches.
- If authentication fails, reply that Life360 is not configured.
- If rate limited, try with `--no-cache` or wait and retry.
- If geocoding fails, still report the coordinates but note that the place could not be resolved.

## Verification
After each `l360` invocation, verify that the command succeeded (exit code 0). If it returns an error, respond with a clear explanation.

## Example Usage

**User:** "Where is Rob?"
**Skill Action:** 
1. Run `l360 member locate Rob` - capture FULL output
2. Geocode to get the full address
3. Report summary: "📍 Rob is at [geocoded address]. Address: [full address]"
4. Prompt: "Would you like more details (battery, coordinates, last seen)?"
5. Only if user says yes, show the full l360 output

**User:** "Show me all family members"
**Skill Action:** Run `l360 member list` and present the member list.

**User:** "Is Deb at home?"
**Skill Action:** 
1. Run `l360 member locate Deb`
2. Compare location to home address
3. Report: "📍 Deb is at [geocoded address]. Would you like more details?"