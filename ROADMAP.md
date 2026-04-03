# Orbitbar Roadmap

## Current Direction
Orbitbar stays a thin HUD, not a second chat client. The next phase is an approval-first triage surface for live agent terminals, with Codex as the primary integration path and Gemini or Claude kept compatible.

## Next Milestone: Approval-First Local Beta
Success means:
- blocked sessions surface in the bar within seconds
- the popup makes the next action obvious
- sensitive flows still hand off to the terminal cleanly
- the feature is reliable enough for daily use on the local setup

## Product Decisions
- Keep Orbitbar as a thin HUD
- Optimize for a polished local beta before broader reuse
- Prioritize faster approvals over feature sprawl

## Key Changes
- Normalize Orbitbar around user-facing states: `Needs input`, `Working`, `Idle`, `Done`, `Error`
- Prioritize urgency in the bar button instead of thread titles
- Restructure the popup into urgent-first triage groups
- Standardize a single primary action per session
- Tighten session summaries so each card explains why it is visible

## Bridge And Data
- Extend bridge output with:
  - `ui_state`
  - `summary`
  - `primary_action`
  - `urgency_rank`
- Read deeper Codex metadata from local session state
- Keep provider adapters separate but normalize them into one session shape
- Preserve the existing security boundary:
  - Orbitbar can focus terminals and send safe choice responses
  - terminals keep password entry and freeform replies

## Implementation Breakdown
### 1. Bridge
- Improve Codex thread matching and live-session deduplication
- Sort by urgency and recency instead of raw status only
- Normalize provider metadata before the UI reads it

### 2. Orbitbar UI
- Update the bar badge and label around pending and active state
- Group popup sessions into urgent, working, and quiet sections
- Add a stronger empty state for “watching live agent terminals”

### 3. Productization
- Add a local config toggle for approval-first Orbitbar
- Keep the behavior documented in the repo for branch collaborators

## Test Plan
- Normal Codex sessions stay non-urgent
- Approval requests rise to the top quickly
- Multiple providers still sort by urgency first
- Inline safe choices reach the correct terminal
- Sensitive flows redirect to terminal focus
- Bridge or state-file interruptions degrade gracefully
- Empty, single-session, and crowded popup layouts stay legible

## Assumptions
- This is local-first, not upstream-first
- Codex is the primary integration target
- The left AI sidebar remains the full conversation surface
- The next milestone is reliability and triage quality, not more scope
