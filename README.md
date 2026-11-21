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
- **Board:** set the outline, sync from the schematic (Update PCB), place and move footprints,
  delete items, configure the stackup and design rules, route a net, add an exact track, pour
  and refill copper zones.
- **Save and export:** `pcb_design_save` returns `saved` only when the schematic and board are
  durably stored. `pcb_board_export_manufacturing` runs the final review and stores a ZIP of
  Gerbers, drill, position and BOM files as a design asset, returning a reference and a
  short-lived URL, never file bytes.
- **Import:** `pcb_design_import_kicad` replaces the design with a KiCad project's text files,
  appends a KiCad project's sheets, or merges another granted design's sheets (`fromDesignId`).
  It always asks you in the editor, even inside a plan.
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

Version 0.2.13 matches the server's catalog version 2. The server and editor are live at
`https://api.deltatronix.io/mcp` and `https://pcb.deltatronix.io`. In the editor's own test
harness, a recorded client builds the reference design (an Arduino Nano board where a
potentiometer dims an LED) from an empty design through these tools only: ERC 0, DRC 0, the
reference netlist, one plan approval, a `saved` receipt and an exported archive, three times in
a row. Please report problems in this repository's issues.

## Changelog

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
   entry, and add a changelog line. Merge.
2. In a second pull request, pin both marketplace entries (`.claude-plugin/marketplace.json`
   and `.agents/plugins/marketplace.json`) to the merged commit:
   `{"source": "url", "url": "https://github.com/Deltatronix/pcb-agent-plugin.git", "sha": "<merge sha>"}`.
   Installs then fetch exactly that commit, whatever lands on `main` later.
3. Tag the pinned content commit `v<version>` and publish a GitHub release with the changelog
   line. Plugin names never change.

## License

MIT for the files in this repository. See [LICENSE](LICENSE). The Deltatronix service is
governed by its own terms.
