# Deltatronix PCB agent

A Claude Code and Codex plugin for [Deltatronix PCB](https://pcb.deltatronix.io). It lets your
coding agent build and edit a design on the platform, schematic and board, in the Deltatronix PCB
editor you have open: inline parts, schematic, outline, placement, routing, copper pours, ERC and
DRC, save, manufacturing export and KiCad import. You approve one plan in the editor; each write
or batch is one undoable transaction with a receipt. It uses your Deltatronix account for PCB access
and your client's own model for reasoning.

## Install

Claude Code:

```sh
claude plugin marketplace add Deltatronix/pcb-agent-plugin
claude plugin install pcb-agent@deltatronix-pcb
```

Or inside a session: `/plugin marketplace add Deltatronix/pcb-agent-plugin`, then
`/plugin install pcb-agent@deltatronix-pcb`.

Codex:

```sh
codex plugin marketplace add Deltatronix/pcb-agent-plugin
codex plugin add pcb-agent@deltatronix-pcb
```

Optional Codex policy that asks for approval before write tools:

```toml
[plugins."pcb-agent@deltatronix-pcb".mcp_servers.pcb]
default_tools_approval_mode = "writes"
```

## Connect

1. Run `/mcp` and connect the `pcb` server. Sign in with your Deltatronix account in the browser
   and approve the consent page (scopes `pcb:read pcb:write`). Codex signs in with
   `codex mcp login pcb --scopes pcb:read,pcb:write --oauth-client-registration dcr`.
2. Open the design in the PCB editor, open the Agent panel, create a design grant with edits
   allowed for the client ID shown at consent, and start the runner.
3. Ask the agent for the work. It reads the design, proposes one plan, and you approve that plan
   in the editor tab. Writes inside the plan then run without further dialogs; Stop in the editor
   ends the plan at once.

Never paste API keys, passwords or tokens into chat. Every tool needs OAuth sign-in, reads
included; platform cookies do not authenticate MCP calls.

### Claude Desktop, claude.ai and ChatGPT

These clients connect to the same server by URL. There is no plugin to install, so the skill
in this repository is not loaded; the server's own instructions still apply.

- Claude Desktop and claude.ai: Settings, Connectors, Add custom connector, URL
  `https://api.deltatronix.io/mcp`. On Team and Enterprise plans an owner adds it for the
  organization. Connect, then sign in with your Deltatronix account.
- ChatGPT: in Settings, turn on developer mode, then add a custom MCP connector with the
  URL `https://api.deltatronix.io/mcp` and OAuth authentication. Sign in when asked.

The server publishes OAuth discovery for these clients: protected-resource metadata, client ID
metadata documents, dynamic client registration and PKCE (S256). Steps 2 and 3 above apply
unchanged: open the design and start the runner, then approve the plan in the editor tab.

## What it can do

Catalog version 2: every call passes `designId` and `catalogVersion: 2`.

- **Plan:** `pcb_plan_propose`, `pcb_plan_get`, `pcb_plan_end`. One approved plan bounds the
  tools, the number of calls and the time.
- **Read:** schematic summary (with sheet placements), symbols, nets and ERC; board summary,
  footprints, nets, regions, DRC (`pcb_board_run_drc`, with schematic parity), stackup, net
  classes and mechanical outline; component search and inspection; inline parts.
- **Schematic:** define a missing part inline (`pcb_part_define`), insert, set fields, add power,
  labels, wires, direct pin connections and no-connect flags, move, rotate, remove, annotate,
  tidy, net classes. A pin is named by its pin name, or by number when the part repeats a name.
- **Board:** set the outline, sync from the schematic (Update PCB) or reload footprints from
  the library, place, autoplace and move footprints, delete items, configure the stackup and
  design rules, autoroute the board or named nets, route a net (with up to two router-placed
  vias), route and tune a differential pair, add an exact track, pour and refill copper zones.
- **Save and export:** `pcb_design_save` returns `saved` only when the schematic and board are
  durably stored. `pcb_board_export_manufacturing` runs the final review and stores a ZIP of
  Gerbers, drill, position and BOM files as a design asset, returning a reference and a
  short-lived URL, never file bytes.
- **Import:** `pcb_design_import_kicad` replaces the design with a KiCad project's text files,
  appends a KiCad project's sheets, or merges another granted design's sheets (`fromDesignId`).
  It always asks you in the editor, even inside a plan. Import and the pair tools sit in the
  `advanced` toolbox, which starts closed (`open_toolbox`).
- **Designs:** `pcb_designs_list` lists the designs your client is granted; `pcb_design_create`
  makes an empty design granted to that client only; `pcb_design_open` moves the connected tab to
  another granted design after you approve; `pcb_design_rename` renames the design.
- **Editor agent:** `pcb_task_run` hands a goal to the engineering agent in the editor's Agent
  panel, which you approve there. A task that runs past 40 seconds answers a `taskId` to poll or
  cancel.

Each write takes the current revision as `expectedRevision` and a new UUID `idempotencyKey`;
reuse a key only for an identical retry. `applied` confirms the editor applied the change,
`verified` that it also checked it, and only `saved` that it is stored. An `uncertain` result has
an unknown outcome: read again and do not resubmit it with a new key. Refused, blocked or
unavailable results come with a reason and are normal stop results.

## Status

Version 0.2.23 matches the server's catalog version 2. The server and editor are live at
`https://api.deltatronix.io/mcp` and `https://pcb.deltatronix.io`. In the editor's own test
harness, a recorded client builds the reference design (an Arduino Nano board where a
potentiometer dims an LED) from an empty design through these tools only: ERC 0, DRC 0, the
reference netlist, one plan approval, a `saved` receipt and an exported archive, three times in
a row. Please report problems in this repository's issues.

## Changelog

- **0.2.23 (2026-11-27):** skill only. Schematic: a placed symbol never lands on another
  symbol, its pins or its text, and each power symbol hangs on one straight wire; the skill reads
  `counts.drawing` (`overlaps`, `detours`) from the summary, ends a step with 0 overlaps
  (`pcb_schematic_tidy` with `"layout": true` fixes one) and reports each detour it leaves.
  `pcb_schematic_connect` and `pcb_schematic_add_power` seat each chain of two-pin parts off a
  pin in a column on that pin's line, with straight wires and the ground symbols of one side on
  one row, so the skill leaves two-pin parts as inserted and reports any the result left
  (Deltatronix-pcb#4831, #4832).
- **0.2.22 (2026-11-27):** skill only. Schematic: `pcb_schematic_connect` wires every pin pair
  of a step in one call (`connections`, up to 64, all or nothing; one pair is a list of one) and
  `pcb_schematic_add_wire` takes points only; the skill wires pin to pin, keeps labels for
  cross-sheet, bus and spread nets, and reports `labelJoinedNets` from the summary. Board:
  connectors, right-angle potentiometers and switches go on a board edge, facing out, through
  `pcb_board_autoplace` (`edge` / `interior` for exceptions); an `access-blocked` warning means
  a part sits in front of one. Plan: the skill asks how the board will be built (compact,
  standard or hand-solder) and records it as the brief's `assembly` item, which sets autoplace
  spacing and the final review's assembly checks; it plans the smallest set of parts and names
  every added part with its reason (Deltatronix-pcb#4788, #4789, #4790, #4791).
- **0.2.21 (2026-11-24):** skill only. Board: `pcb_board_autoroute` takes `effort`
  `"quick"` (one pass in net order), `"normal"` (the default: rip-up and retry passes) or
  `"thorough"` (more passes, slowest). On a large board use `"quick"`, and route in parts with
  `nets` if it still passes the 90 s write window (Deltatronix-pcb#4664, #4663;
  Deltatronix-backend#1083).
- **0.2.20 (2026-11-24):** skill only. Board: `pcb_board_autoroute` routes every unrouted
  connection of the board, or of the nets named in `nets`, in one undo, and reports
  routed/total, vias and each connection left unrouted with its reason (`blocked`, `budget`,
  `drc`, `pair-pending`, `cancelled`); pour the planes first, treat an unrouted list as an
  honest result, and repair single connections with `pcb_board_route_net`. It leaves a pair's
  nets to `pcb_board_route_pair` and is never a `pcb_batch_write` operation. `effort` takes
  `"normal"` only for now. It routes before asking, so the approval names the result and can
  take a minute on a large board; a call past the 90 s write window answers `timed_out` and
  adds nothing, so route that board in parts with `nets` (Deltatronix-pcb#4664;
  Deltatronix-backend#1082).
- **0.2.19 (2026-11-23):** skill only. Toolboxes: the new `advanced` toolbox starts closed and
  holds `pcb_board_route_pair`, `pcb_board_tune_pair` and `pcb_design_import_kicad`; open it
  with `open_toolbox` (in Codex it appears in the next session, and the pair writes work now as
  `pcb_batch_write` operations). Board: `pcb_board_autoplace` places parts by reference inside
  the outline, keeping rotation and side, in one undo; `pcb_board_route_net` tries every shared
  layer, then places up to two through vias itself (`routing.vias`), keeps inner power planes
  whole, and sends a paired net to `pcb_board_route_pair`; the pair tools take millimetres and
  their limits from the approved brief; `pcb_board_sync_components` takes `reloadFootprints`
  (on its own, names where else each footprint is used; run DRC after). Parts:
  `pcb_part_define` returns a `preview` (SVG, or text past 6000 characters), takes
  `replace: true` and `remove: true` (`INLINE_PART_IN_USE` while placed), and refuses off-grid
  pins, stems off the body, SMD pads without mask and tight courtyards with the fix
  (Deltatronix-pcb#4633, #4634, #4639, #4641, #4642; Deltatronix-backend#1068).
- **0.2.18 (2026-11-23):** skill only. Import: the skill lists the modern KiCad files the tool
  takes (no legacy KiCad 5 or library files, one `.kicad_pro`), how to send a project over
  4 MiB in parts (`importId`, `part`, `final`), the `import` report and its warnings (weak
  library links, unknown pin types and the rest of File > Open's log), and what
  `IMPORT_FAILED` and `IMPORT_PARTLY_APPLIED` now say; a replace without a `.kicad_pcb` keeps
  the board. Export saves first (`SAVE_FAILED`), names the variant in its receipt, gives a next
  step for `SUPERSEDED_REVIEW`, `CANCELLED`, `GENERATION_UNAVAILABLE` and `STALE_ZONE_FILLS`,
  and takes the 2-layer or the new 4-layer preset
  (`jlcpcb-4l-fr4-1oz-green-routed-no-vcut-v1`, F.Cu/In1.Cu/In2.Cu/B.Cu, 1 oz). Results list
  the split write refusals `READ_ONLY`, `ROOM_CLOSED`, `DECLINE_COOLDOWN`,
  `INVALID_IDEMPOTENCY_KEY` and `STALE_REVISION` (with the current revision) and what to do
  for each, and say that a collaborator's edits in a shared room no longer stop a step
  (Deltatronix-pcb#4619, #4620, #4621, #4623, #4624, #4626).
- **0.2.17 (2026-11-23):** skill only. The skill teaches the engineering bar the final review
  now checks: `pcb_part_define` draws an F.Fab outline with a pin-1 bevel by default, at `K`
  for a diode or LED and at `+` for a polarized capacitor, and the agent adds a silk outline
  clear of the pads; each IC supply pin gets its own decoupling capacitor, placed close to the
  pin (the review warns above 3.5 mm); I2C lines get pull-ups unless a module carries them; USB
  and power connectors go at the board edge. The export example shows the optional `pin-1` and
  `polarity` checks, and the agent fixes the receipt's "Not verified" warnings before it
  reports a passed review (Deltatronix-pcb#4615, #4616).
- **0.2.16 (2026-11-23):** skill only. `pcb_plan_propose` no longer offers
  `requirements.placement` or `inputArtifacts`: `requirements` takes only `brief` and
  `finalReview`, and the server refuses any other key by name. The skill also covers the
  latest tool behaviour: `pcb_schematic_add_label` `aliases` (rename, redefine or delete a bus
  alias), a wire that would join two named nets refuses, a reference names every unit of a
  part (`units[]`, Value on every unit), `pcb_board_get_net` and `pcb_board_get_region` return
  item ids for `pcb_board_delete_items`, summary counts ignore page filters, and refusals name
  the failing argument with an example in millimetres. `scripts/check-skill.sh` keeps the
  refused keys out (Deltatronix-pcb#4610, #4145).
- **0.2.15 (2026-11-23):** skill only. An approved plan that checks or exports pins extra
  expertise from the design's brief (thermal, physics, signal integrity, EMC), and an approved
  `pcb_plan_get` returns those skills: the skill no longer says pinned skills never change during
  the plan, and tells the client to follow them when it verifies and reviews.
  `scripts/check-skill.sh` checks this text (Deltatronix-pcb#3398, #4145).
- **0.2.14 (2026-11-22):** skill only. The plan step no longer tells clients to send
  `expectedRevision` to `pcb_plan_propose`, whose schema refuses it, so a plugin client's first
  plan call no longer fails validation. A final review too large to list is paged with
  `pcb_board_get_final_review`. `scripts/check-skill.sh` keeps the plan step free of
  `expectedRevision` (Deltatronix-pcb#4145, #4208, #3406).
- **0.2.13 (2026-11-21):** skill only. `pcb_design_merge` is folded into `pcb_design_import_kicad`:
  merge another design with `{"mode": "append", "fromDesignId": "..."}`, behind the same
  approval as any import. The skill also documents KiCad `mode: "append"`. Ship with the server
  that drops `pcb_design_merge` (Deltatronix-pcb#4186).
- **0.2.12 (2026-11-21):** skill only. A `pcb_task_run` task whose editor tab stops reporting
  now ends as `timed_out` after 150 seconds, not 60 (Deltatronix-pcb#4192). Needs the server
  from the same release; an older server still ends it after 60 seconds.
- **0.2.11 (2026-11-21):** skill only. `pcb_task_run` waits up to 40 seconds per call and then
  answers `running` with a `taskId`: the skill covers polling with `taskId`, `cancel: true`, what
  `running` and `progress` mean, the 60-second silent-tab limit, and that a revoked grant ends
  polling (Deltatronix-pcb#4192). An unknown, expired or pre-restart `taskId` refuses
  `TASK_HANDLE_UNKNOWN`; an older server refuses it without that reason.
- **0.2.10 (2026-11-21):** skill only. Covers the design tools (`pcb_designs_list`,
  `pcb_design_create`, `pcb_design_open`, `pcb_design_merge`, `pcb_design_rename`), `pcb_task_run`,
  and `pcb_schematic_add_sheet` adding pins to an existing sub-sheet or placing a sheet file again
  (Deltatronix-pcb#3403, #4192, #3397). The server already serves these tools.
- **0.2.9 (2026-11-20):** skill only. `pcb_plan_propose` returns the engineering skills it
  pinned for the plan (`skills`); the skill tells the client to follow them and to report an
  unavailable one rather than invent its rules (Deltatronix-pcb#3392). Needs the server from
  the same release; with an older server the result has no `skills` and nothing changes.
- **0.2.8 (2026-11-20):** listing metadata only: privacy policy URL for Claude Code; long
  description, category, website, privacy and terms URLs and starter prompts for Codex. Connection
  steps for Claude Desktop, claude.ai and ChatGPT. Tools, skill and server are unchanged.
- **0.2.7 (2026-11-19):** sub-sheets, hierarchical labels and buses: `pcb_schematic_add_sheet`,
  and `pcb_schematic_add_label` with `kind: "hierarchical"` and vector bus nets
  (Deltatronix-pcb#4187). Needs the server from the same release.
- **0.2.6 (2026-11-19):** toolboxes for clients with a tool limit: `list_toolboxes`,
  `open_toolbox` and `close_toolbox` (Deltatronix-pcb#4192). Needs the server from the same release.
- **0.2.5 (2026-11-17):** build with `pcb_batch_write`: one schematic batch,
  one board batch and one pour batch, then save and export; adds plan accounting, checks and
  refusal recovery guidance (Deltatronix-pcb#4253).
- **0.2.4 (2026-11-17):** moves guidance and examples from the shortened MCP tool
  descriptions into the skill; tools and arguments are unchanged.
- **0.2.3 (2026-11-17):** needs the editor and server from the same release.
  - Inside a plan, writes answer `applied` or `verified` without waiting for the save; call
    `pcb_design_save` after the last edit, the only planned call that answers `saved`.
  - The pin tools take lists. `pcb_schematic_add_no_connect`, `pcb_schematic_add_power` and
    `pcb_schematic_add_label` take targets (a part and some of its pins), up to 256 pins per
    call, all or nothing; the single-pin shape is gone. `pcb_schematic_insert_components`
    takes each part's `value`.
  - The skill waits for plan approval with `pcb_plan_get` and `waitSeconds: 30` (repeat while
    `pending`) instead of polling.
- **0.2.2 (2026-11-14):** every length and coordinate is in millimetres, in arguments and in
  board read results (fields that were `*Nm` are now `*Mm`; sync positions, regions and
  inline-part symbols are mm). The skill
  syncs footprints without positions, then places each one with `pcb_board_place_footprint`.
  Needs the editor and server from the same release.
- **0.2.1 (2026-11-13):** skill only. A revision belongs to one editor tab, so a reopened
  design reports new revisions for the same saved content. Export without final-review facts
  is refused with a copyable example: end the plan and propose one that carries them.
- **0.2.0 (2026-11-13):** catalog version 2 (version 1 is refused). The plan workflow: propose
  one plan, the user approves it once in the editor, writes carry its `planId`. Build tools for
  the whole design: inline parts, schematic drawing and ERC, outline, sync and placement,
  stackup and rules, routing, tracks and pours, DRC with parity. `pcb_design_save`,
  `pcb_board_export_manufacturing` and `pcb_design_import_kicad`. The skill describes the
  build order and the export requirements.
- **0.1.0 (2026-11-11):** first public release. Shared skill, Claude Code and Codex manifests,
  and the `pcb` MCP server.

## Releasing

1. Bump `version` in `.claude-plugin/plugin.json`, `plugin.json` and the Claude marketplace
   entry, and add a changelog line. Run `scripts/check-skill.sh` and
   `claude plugin validate --strict .`. Merge.
2. In a second pull request, pin both marketplace entries (`.claude-plugin/marketplace.json`
   and `.agents/plugins/marketplace.json`) to the merged commit:
   `{"source": "url", "url": "https://github.com/Deltatronix/pcb-agent-plugin.git", "sha": "<merge sha>"}`.
   Installs then fetch exactly that commit, whatever lands on `main` later.
3. Tag the pinned content commit `v<version>` and publish a GitHub release with the changelog
   line. Plugin names never change.

## License

MIT for the files in this repository. See [LICENSE](LICENSE). The Deltatronix service is
governed by its own terms.
