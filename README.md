# Deltatronix PCB agent

A Claude Code and Codex plugin for [Deltatronix PCB](https://pcb.deltatronix.io). It lets your
coding agent build and edit a design on the platform, schematic and board, in the Deltatronix PCB
editor you have open: inline parts, schematic, outline, placement, routing, copper pours, ERC and
DRC, save, manufacturing export and KiCad import. You approve one plan in the editor; every edit
is its own undoable transaction with a receipt. It uses your Deltatronix account for PCB access
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

Other clients that support remote MCP servers with OAuth (Claude Desktop, ChatGPT custom
connectors) can use the same server URL: `https://api.deltatronix.io/mcp`.

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
- **Import:** `pcb_design_import_kicad` replaces the design with a KiCad project's text files.
  It always asks you in the editor, even inside a plan.

Each write takes the current revision as `expectedRevision` and a new UUID `idempotencyKey`;
reuse a key only for an identical retry. `applied` confirms the editor applied the change,
`verified` that it also checked it, and only `saved` that it is stored. An `uncertain` result has
an unknown outcome: read again and do not resubmit it with a new key. Refused, blocked or
unavailable results come with a reason and are normal stop results.

## Status

Version 0.2.1 matches the server's catalog version 2. The server and editor are live at
`https://api.deltatronix.io/mcp` and `https://pcb.deltatronix.io`. In the editor's own test
harness, a recorded client builds the reference design (an Arduino Nano board where a
potentiometer dims an LED) from an empty design through these tools only: ERC 0, DRC 0, the
reference netlist, one plan approval, a `saved` receipt and an exported archive, three times in
a row. Please report problems in this repository's issues.

## Changelog

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

## License

MIT for the files in this repository. See [LICENSE](LICENSE). The Deltatronix service is
governed by its own terms.
