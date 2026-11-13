---
name: pcb-agent
description: Build, edit, check, save and export a Deltatronix PCB design (schematic and board) through the connected PCB editor, under one plan the user approves. Use for any Deltatronix design work - reading a design, drawing a schematic, defining a missing part, placing, routing, pouring, DRC, saving, exporting manufacturing files or importing a KiCad project.
---

# PCB agent

Everything runs in the user's open PCB editor tab: geometry, routing, ERC, DRC,
fills and export. You send MCP calls; the editor applies them, each as its own
undoable transaction with a receipt. Work on the platform, never in local KiCad
files.

## 1. Connect

1. Ask the user to open the design at `https://pcb.deltatronix.io/d/<designId>/pcb`,
   open the Agent panel, create a design grant for your client ID (shown on the
   consent page) with edits allowed, and start the runner.
2. Sign in through your client's native MCP connection UI and the Deltatronix
   consent page, with scopes `pcb:read pcb:write`. Never ask for API keys,
   passwords or tokens in chat. Reads need sign-in too.
3. If a tool answers `unavailable` with "open the design", ask the user to open
   the tab and start the runner. "The editor and server tool lists differ" means
   the tab is stale: ask the user to reload it.

## 2. Every call

- Pass `designId` and `catalogVersion: 2`. Version 1 is retired.
- Writes also take the current domain `revision` as `expectedRevision` (from your
  latest read of that domain, schematic or board) and a new UUID
  `idempotencyKey`. Reuse a key only for an identical retry.
- Inside an approved plan, pass its `planId` on every write.
- Read results carry `revision`; write results carry `receipt.transactionId`,
  the new `revision`, and for schematic writes a `diff`.

## 3. Observe, then one plan

1. Read first: `pcb_schematic_get_summary` (counts, ERC and the sheet placements:
   `sheets.items[].sheetInstanceId`, which inserts need) and
   `pcb_board_get_summary`. Use the returned revisions.
2. Propose one plan with `pcb_plan_propose`: a `title`, `steps`
   (`{summary, tools[]}` the user reads), `maxCalls` (all writes the plan may
   make, up to 500), `expiresInMinutes` (up to 120), `expectedRevision`, and
   for export the `requirements` below.
3. Tell the user to approve it in the editor tab, then poll `pcb_plan_get` until
   `status` is `approved`. A declined, stopped or expired plan stops the work.
4. Writes in the plan's tools run without further dialogs. A tool outside the
   plan, a spent budget, an expired or stopped plan is refused. One active plan
   per client and design: end it with `pcb_plan_end` before proposing another.
   Count calls generously; the user can stop the plan at any time.
5. Without a plan, every write raises its own approval dialog. Do not do that
   for a build.

## 4. Build a design

Units: schematic positions are sheet millimetres on the 1.27 mm grid; board
tools take millimetres, except `pcb_board_sync_components` positions and the
`*Nm` fields, which are integer nanometres.

**Parts.** `pcb_components_search` / `pcb_components_inspect` find library
parts (insert them by `decisionId`). A part the library lacks is defined once
with `pcb_part_define`: symbol pins in 2.54 mm grid units (+y down, x/y is the
pin's connection point), footprint pads in millimetres with drill for
through-hole, a courtyard, and `pinToPad`. Its id is
`inline:<name in lowercase, non-alphanumerics as ->`.

**Schematic.**
1. `pcb_schematic_insert_components`: references, `sheetInstanceId` from the
   summary, `inlinePartId` or `decisionId`, positions. Leave room: a wire between
   two pins must not cross a third pin.
2. `pcb_schematic_set_symbol_field` for Value (and Footprint, Datasheet).
3. Power: `pcb_schematic_add_power` per pin (`rail` such as `+5V`, `GND`); it
   adds one PWR_FLAG only when nothing drives the rail.
4. Signals: `pcb_schematic_add_label` with the same `net` on each pin (`global`
   labels give board nets those exact names), or `pcb_schematic_connect` for a
   direct wire, then a label to name it.
5. `pcb_schematic_add_no_connect` on every unused pin.
6. A pin is its embedded name, or its number when the part repeats that name
   (an Arduino Nano's two GND pins are `4` and `29`). An ambiguous name is
   refused with the numbers to use.
7. `pcb_schematic_list_erc` until it is empty.

**Board.**
1. `pcb_board_set_outline` with `rect {x, y, width, height}` or closed segments.
2. `pcb_board_sync_components` (Update PCB) with a position (nm), rotation and
   side for every new reference, then `pcb_board_place_footprint` to adjust
   (mm). `pcb_board_list_footprints` reads them back.
3. `pcb_board_configure_stackup`, for example 2 copper layers and one FR4
   dielectric: export needs an explicit stackup.
4. `pcb_board_configure_design_rules` for board minimums (nanometres).
5. Route each connection with `pcb_board_route_net` (`fromRef/fromPad`,
   `toRef/toPad`, `layer`, `widthNm`). Use the other layer where routes cross. A
   search that stops short returns `partial` and adds nothing: change the layer
   or placement, or draw an exact path with `pcb_board_add_track`.
6. `pcb_board_pour_copper_zone` (for example `GND` on `B.Cu`).
7. `pcb_board_run_drc`: errors, warnings and unconnected items, with schematic
   parity when the schematic has parts. Fix until it is clean.

**Save.** `pcb_design_save` waits until the sheets and the board are durably
stored and returns `saved` with both revisions, or `timed_out` / `uncertain`
with a reason. It needs no plan entry and may be called with any revision.

**Export.** `pcb_board_export_manufacturing` runs the final review, then stores a
ZIP (Gerbers incl. mask and silk, drill, position, BOM) as a design asset and
returns `artifact` (assetId, filename, sha256, file list, short-lived URL), never
file bytes. The approved plan must list it and carry:

```json
"requirements": {
  "brief": { "version": 1, "items": [
    { "id": "erc", "kind": "requirement", "text": "ERC clean", "category": "user_decision", "provenance": "user", "approval": "approved" },
    { "id": "drc", "kind": "requirement", "text": "DRC clean", "category": "user_decision", "provenance": "user", "approval": "approved" },
    { "id": "stackup", "kind": "stackup", "text": "2-layer FR4, GND plane on B.Cu", "value": { "referencePlane": { "net": "GND", "layer": "B.Cu" } }, "category": "user_decision", "provenance": "user", "approval": "approved" }
  ] },
  "finalReview": {
    "manufacturingPreset": "jlcpcb-2l-fr4-1oz-green-routed-no-vcut-v1",
    "artifactKinds": ["gerber", "drill", "bom", "placement"],
    "checks": [
      { "requirementId": "erc", "selector": { "kind": "erc" }, "applicability": "required" },
      { "requirementId": "drc", "selector": { "kind": "drc" }, "applicability": "required" }
    ]
  }
}
```

A `REVIEW_NOT_READY` refusal lists what blocks it (unmet requirements, critical
findings, what it could not verify). Fix those and export again.

## 5. Import a KiCad project

`pcb_design_import_kicad` with `mode: "replace"` and `files: [{path, text}]`
replaces the design's schematic and board with a KiCad project (`.kicad_pro`,
`.kicad_sch`, `.kicad_pcb`; 4 MiB in all). It always
asks the user in the editor, even inside a plan: call it without `planId`.

## 6. Results

- `applied`: the editor applied the change. `verified`: it also checked it.
  `saved`: it is durably stored. Never claim a save without a `saved` receipt.
- `uncertain`: the outcome is unknown. Read again; do not resend under a new key.
- `refused` comes with a reason and usually a message with a valid example. It
  is a normal stop: read the reason, fix the call or the design, and do not
  invent other tools. `STALE_REVISION` means read again first.
- Report what you built from read-backs (ERC, DRC, nets, footprints), not from
  your own plan.
