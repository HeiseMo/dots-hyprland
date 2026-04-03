# CLI-First Skills Roadmap

This document captures the next useful layer on top of the CLI-first provider stack:

- `Codex CLI`
- `Gemini CLI`
- `Claude Code`
- `Kimi Code CLI`
- `Kimi API`

The goal is to make the shell more helpful without bringing back generic API
function-calling as the main architecture.

## Principles

- Keep providers focused on text generation and agent reasoning.
- Keep tool execution mediated by Quickshell.
- Prefer shared capabilities over provider-specific hacks.
- Make risky actions explicit and reviewable.
- Use lightweight desktop context automatically.
- Keep the network-backed `Kimi API` path optional and clearly separate.

## First-Priority Skills

### 1. `workspace_context`

Purpose:
- Show and change the current working directory per CLI provider.
- Make repo-aware chats feel grounded.

What to build:
- `Ai.qml`
  - persist per-model `cwd`
  - expose current workspace to the UI
- `AiChat.qml`
  - `/cwd`
  - visible workspace indicator
- future
  - recent-workspace picker
  - "pin workspace to model" behavior

Why it matters:
- Most agent quality issues in coding workflows are really context issues.

### 2. `read_only_repo_inspect`

Purpose:
- Give every provider reliable, read-only repo context.

What to expose:
- repo root
- file tree summary
- `rg` search summaries
- git status
- current branch
- optional diff summary

Suggested UX:
- slash commands:
  - `/repo status`
  - `/repo tree`
  - `/repo grep QUERY`
- compact shell-generated summaries injected into the transcript

Why it matters:
- This is the safest high-value capability for coding models.

### 3. `command_approval`

Purpose:
- Normalize command proposals across providers.

What to build:
- one Quickshell approval card component
- one shared action object:
  - `title`
  - `command`
  - `risk`
  - `provider`
  - `cwd`
  - `reason`
- provider parsers map shell-action hints into this format

Notes:
- Codex already has partial approval plumbing
- Claude/Gemini/Kimi can later emit explicit proposal blocks or structured hints

Why it matters:
- Safe agent UX depends on consistent approval behavior, not on provider trust.

### 4. `apply_patch_review`

Purpose:
- Make model-proposed edits readable before they land.

What to build:
- detect patch-like output
- render it in a diff-style block
- later allow:
  - copy patch
  - save patch
  - apply patch after approval

Why it matters:
- Models are much more useful when their code-change intent is legible.

### 5. `desktop_context`

Purpose:
- Provide small but valuable shell context automatically.

Default context:
- distro
- current datetime
- focused app / window class
- workspace name/id
- monitor name
- clipboard text availability

Optional context:
- recent notifications summary
- media playback state
- network / battery summary

Why it matters:
- This keeps the sidebar assistant grounded in the current desktop session.

### 6. `research_bundle`

Purpose:
- Make the network-backed path useful without turning every provider into a web tool.

Best fit:
- `Kimi API`
- optionally `Gemini CLI`

Capabilities:
- search request framing
- result summarization
- docs / article condensation
- extract links and claims into a compact response block

Why it matters:
- Coding agents and research agents have overlapping but different strengths.

### 7. `screenshot_context`

Purpose:
- Let the user ask the model about the current screen without full always-on vision.

What to build:
- capture current screen / region
- attach image path or OCR summary into the request
- later add:
  - "explain this error dialog"
  - "summarize this webpage"
  - "what is selected here?"

Why it matters:
- This is the cleanest way to add visual help while keeping privacy sane.

## Suggested Execution Order

1. `workspace_context`
2. `read_only_repo_inspect`
3. `command_approval`
4. `apply_patch_review`
5. `desktop_context`
6. `screenshot_context`
7. `research_bundle`

## Concrete Next Milestones

### Milestone A: Coding Context

Ship:
- `/cwd`
- workspace chip in the composer
- `/repo status`
- `/repo grep`
- `/repo tree`

Outcome:
- every CLI provider becomes meaningfully better for project work

### Milestone B: Safe Actions

Ship:
- shared command approval cards
- command execution result blocks
- provider-to-approval parser adapters

Outcome:
- agents can suggest actions without turning the UI into chaos

### Milestone C: Visual + Research

Ship:
- screenshot attach flow
- Kimi API research prompts
- result summarization cards

Outcome:
- the shell gets stronger at troubleshooting and web-heavy tasks

## Notes on Provider Roles

### Codex CLI
- strongest default coding agent
- best target for approval and patch review

### Gemini CLI
- strong general-purpose reasoning and research
- good fit for desktop context and screenshot workflows later

### Claude Code
- good read-heavy repo analysis
- keep safer by default

### Kimi Code CLI
- useful as an alternative coding agent
- treat as higher-risk until its print-mode safety story improves

### Kimi API
- explicit network fallback
- best place for research-oriented skills

