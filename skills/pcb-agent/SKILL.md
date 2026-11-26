---
name: pcb-agent
description: Build, edit, check, save and export a Deltatronix PCB design (schematic and board) through the connected PCB editor, under one plan the user approves. Use for any Deltatronix design work - listing, creating, opening, renaming or merging designs, reading a design, drawing a schematic, defining a missing part, placing, routing, pouring, DRC, saving, exporting manufacturing files or importing a KiCad project.
---

# PCB agent

Everything runs in the user's open PCB editor tab: geometry, routing, ERC, DRC,
fills and export. The editor applies each write or batch as one undoable
transaction with a receipt. Work on the platform, never in local KiCad files.

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
4. Which design: `pcb_designs_list` (`{}`) lists the designs your client is
   granted, with `designId`, names, `allowWrite` and `editorUrl`. Pass that
   `designId`. A design missing from the list is not granted to you; only the
   user can grant it, in that design's Agent panel.
5. A new design: `pcb_design_create` with `name` and exactly one of `projectId`
   (a project the user owns, from `pcb_designs_list`) or `projectName` (makes a
   new project). It needs the `pcb:write` scope, raises no dialog and needs no
   plan. The new empty design is granted, with edits allowed, to your client
   only, never to other clients. It answers `saved` with `designId` and
   `editorUrl`; no editor has it open yet (next item).
6. Another design in the connected tab: `pcb_design_open` with `designId`. It
   works only for a design already granted to your client. Otherwise it
   refuses `DESIGN_NOT_GRANTED` with the link where the user grants your client:
   pass that link on and stop, do not retry. When a tab is connected for one of
   your other granted designs, the user approves the move in that tab (the
   design it leaves keeps its edits), and the answer `observed` means the new
   design is open and connected. `NO_CONNECTED_EDITOR`: no tab is connected;
   ask the user to open `editorUrl` and connect it. "has not connected it yet":
   call `pcb_design_open` again shortly. These three tools take only the
   arguments named here, no `catalogVersion` or revision.
7. Toolboxes, for clients that limit how many tools they show. The `pcb_board_*`,
   `pcb_schematic_*` and parts tools (`pcb_part_*`, `pcb_components_*`,
   `pcb_footprints_*`) sit in the `board`, `schematic` and `parts` toolboxes.
   The `advanced` toolbox holds `pcb_board_route_pair`, `pcb_board_tune_pair`
   and `pcb_design_import_kicad` (KiCad import and design merge). Plan, the
   other design tools (`pcb_design_*`, `pcb_designs_list`), task and batch
   tools are always listed. `board`, `schematic` and `parts` start open;
   `advanced` starts CLOSED. If a `pcb_*` tool you need is missing from your
   tools, call `list_toolboxes`, then `open_toolbox` with the toolbox that
   holds it (`{"toolbox": "advanced"}`), and `close_toolbox` the ones this task
   does not need. Closing only hides tools from the list; it never blocks a
   call. The choice is kept for your client. A client that does not refresh
   its list on `notifications/tools/list_changed` shows the change in its next
   session: in Codex a newly opened toolbox appears only in the next session.
   Meanwhile the pair writes stay reachable in this session as
   `pcb_batch_write` operations (`{"tool": "pcb_board_route_pair", "args":
   {...}}`); an import cannot be a batch operation, so it waits for the next
   session.

## 2. Every call

- The server instructions only say "Deltatronix PCB tools; follow the pcb-agent
  skill." This skill is the place for the tool rules and examples.
- Every length and coordinate in arguments and results is in millimetres. An
  `Mm` suffix names the unit; unsuffixed coordinates such as `x` and `y` are
  millimetres too. Reads return `units: "mm"`, so a position you read can be
  passed straight back. Schematic positions are sheet coordinates on the
  1.27 mm connection grid.
- Pass `designId` and `catalogVersion: 2`. Version 1 is retired.
- Writes also take the current domain `revision` as `expectedRevision` (from your
  latest read of that domain, schematic or board) and a new UUID
  `idempotencyKey`. Reuse a key only for an identical retry.
- "Plan required" in a tool description means the write belongs inside an
  approved plan: get `planId` from an approved `pcb_plan_propose` and pass it on
  every write in that plan. Without a plan, the write asks the user in its own
  dialog (section 3, item 5). Native edit admission still applies. See Save and
  Import for their exceptions. Batches always need a plan.
- Read results carry `revision`; write results carry `receipt.transactionId`,
  the new `revision`, and for schematic writes a `diff`.
- A revision belongs to one editor tab. A reopened design or another tab
  reports new revisions for the same saved content: read again, and compare
  content, not revisions, across sessions.

## 3. Observe, then one plan

Observation results are bounded pages. Narrow by reference, sheet, net, region
or severity, or use a smaller `pageSize`. For `pcb_schematic_list_symbols` and
`pcb_board_list_footprints`, request fewer fields too.

1. Read first: `pcb_schematic_get_summary` (counts, ERC and the sheet placements:
   `sheets[].sheetInstanceId`, which inserts need) and
   `pcb_board_get_summary` with a small `pageSize`. Use the returned revisions.
   Ask how the board will be built unless the design's brief already says:
   compact (smallest, machine assembled), standard, or hand (easy to solder
   by hand: more room between parts and larger packages). Put the answer in
   the plan's `requirements.brief.items` as
   `{"id": "assembly", "kind": "assembly", "text": "Hand-soldered board",
   "value": {"profile": "hand"}, "category": "user_decision", "provenance":
   "user", "approval": "approved"}`. `pcb_board_autoplace` then keeps 0.25,
   1 or 2.5 mm between parts, and the final review reports parts closer
   (`assembly-spacing`) or smaller (`assembly-package`) than the profile
   allows. Pick packages to match: hand means 0805 or larger passives and
   leaded or through-hole parts.
2. Propose one plan with `pcb_plan_propose`: a `title`, `steps`
   (`{summary, tools[]}` the user reads), `maxCalls` (one per batch operation
   plus other planned writes, up to 500), `expiresInMinutes` (up to 120),
   and for export the `requirements` below. The plan itself takes no revision:
   each write carries its own.
   Keep the title to one line naming what you build or change. Steps are read
   in order; each summary is one line in the approval dialog. A new plan
   returns `planId` with status `pending`. Expiry starts after approval.
   List `pcb_batch_write` and every inner tool in the steps' `tools`;
   `PLAN_TOOL_NOT_ALLOWED` names any missing tool.
   The result's `skills` are the Deltatronix engineering skills pinned for this
   plan: the coordinator's and one per kind of planned write (schematic,
   components, placement, routing, zones, final review). Follow each available
   skill's `prompt` for the work its `applicability` names, in addition to this
   skill; where they conflict on a tool's mechanics, this skill wins. A skill
   with `availability: "unavailable"` has no text yet: say so, do not invent
   its rules. `pcb_plan_get` lists every pinned version under `plan.skills`.
   When the plan checks or exports (ERC, DRC, final review, manufacturing
   export), the approval adds the expertise the design's brief calls for
   (such as thermal, physics, signal integrity, EMC): an approved
   `pcb_plan_get` returns those skills under `skills`, so follow their
   prompts when you verify and review. Pins do not change after approval.
3. Tell the user to approve it in the editor tab, then call `pcb_plan_get` with
   `waitSeconds: 30`. Repeat while the status is `pending`. A declined, stopped
   or expired plan stops the work.
4. Writes in the plan's tools run without further dialogs. A tool outside the
   plan, a spent budget, an expired or stopped plan is refused. One active plan
   per client and design: end it with `pcb_plan_end` before proposing another.
   Proposal rate limits also refuse. End the plan when its work is done;
   committed transactions remain undoable.
5. Without a plan, writes that support individual approval raise their own
   dialog. Do not do that for a build.

## 4. Build a design

After plan approval, build in this order. The per-tool steps below are the
reference for each operation's `args`.

1. One schematic `pcb_batch_write` with `check: true`: define missing parts
   first in that same batch, then insert, power, labels, connect, label,
   no-connect.
2. Read `pcb_board_get_summary` again with a small `pageSize`: a schematic
   commit moves the board revision. Use this revision for the board batch.
3. One board `pcb_batch_write`: outline, sync, placements, stackup, rules,
   routes.
4. One pour batch with `check: true`: the copper pour (for example GND on
   B.Cu), alone.
5. `pcb_design_save`, then `pcb_board_export_manufacturing` (requirements below).

**Parts.** `pcb_components_search` / `pcb_components_inspect` find library
parts (insert them by `decisionId`). A part the library lacks is defined once
with `pcb_part_define`: symbol body and pins in mm (+y down, x/y is the pin's
connection point, on the 1.27 mm grid, and the pin's stem ends on the body's
edge), footprint pads in millimetres with drill for through-hole, a
courtyard, and `pinToPad`. Its id is
`inline:<name in lowercase, non-alphanumerics as ->`. Without `fab`, the
footprint gets an F.Fab outline (the courtyard less 0.25 mm) with a pin-1
bevel. On a two-pad part whose symbol has a pin named `K`, `Cathode`, `+` or
`-`, the bevel goes on that pin's pad, so name a diode's or LED's cathode `K`
and a polarized capacitor's positive pin `+`. No silk is drawn for you: add a
`silk.outline` that stays clear of every pad (silk on a pad is a DRC
warning).

A definition the checks refuse names each problem with its fix; apply it and
send the definition again:

- a pin off the 1.27 mm grid gives the position to use;
- a pin whose stem misses the body gives the `x` or `y` that lands it on the
  body's edge;
- an SMD pad on `F.Cu` without `F.Mask` (or `B.Cu` without `B.Mask`) gets no
  solder-mask opening: give it `["F.Cu", "F.Paste", "F.Mask"]`;
- pads within 0.25 mm of the courtyard give one finding with a courtyard
  rectangle that passes.

A part already defined refuses `INLINE_PART_EXISTS`. To repair one, read it
with `pcb_part_get` and send the whole definition again with `replace: true`:
the part is redefined, its footprint variants kept, and every placed symbol of
it redrawn in the same transaction (one undo). The board keeps the old
footprint until you reload it (`pcb_board_sync_components` with
`reloadFootprints`, Board below). `{"name": "...", "remove": true}` (nothing
else) deletes an unplaced part; a placed one refuses `INLINE_PART_IN_USE`
naming its references: remove those symbols with `pcb_schematic_remove_symbol`
first, or repair the part with `replace: true`. A single `pcb_part_define`
call (not a batch operation) returns `preview`: the symbol as `{svg}`, or as
`{text}` (body size and pins per side) when the SVG is over 6000 characters.
Check it before you insert the part. Without a plan, the approval dialog draws
the symbol and footprint for the user.

**Schematic.**

1. `pcb_schematic_insert_components`: references, `sheetInstanceId` from the
   summary, `inlinePartId` or `decisionId`, positions, and each part's `value`
   (`"10k"`, `"220R"`), set on insert. Leave room: a wire between two pins must
   not cross a third pin. Give each IC supply pin its own decoupling capacitor
   to ground, and each I2C line (SDA, SCL) a pull-up resistor to its rail
   unless a module on the bus carries its own.
   `pcb_schematic_set_symbol_field` changes a Value later (and Footprint,
   Datasheet).
2. The pin tools take lists. A target is one part and some of its pins:
   `{"reference": "A1", "pins": ["D2", "D3"]}`. Up to 64 targets per list, 32
   rails or labels per call and 256 pins per call. A call is all or nothing: the
   first pin refused refuses the whole call and the reason starts with that pin
   (`A1.D7: ...`). A pin already in the requested state is skipped and counted.
3. Power: `pcb_schematic_add_power` with every rail in one call; it adds one
   PWR_FLAG per rail only when nothing drives that rail:
   `{"rails": [{"rail": "+5V", "targets": [{"reference": "A1", "pins": ["5V"]}]},
   {"rail": "GND", "targets": [{"reference": "A1", "pins": ["4", "29"]}]}]}`
4. Signals: `pcb_schematic_add_label`, one entry per net with all its pins
   (`global` labels give board nets those exact names):
   `{"labels": [{"net": "POT", "kind": "global", "targets": [{"reference": "A1",
   "pins": ["A0"]}, {"reference": "RV1", "pins": ["W"]}]}]}`. Or
   `pcb_schematic_connect` for a direct wire, then a label to name it.
5. Sub-sheets and buses: `pcb_schematic_add_sheet` adds a block under the
   root (or `sheet`) with its pins, `{"name": "Driver", "pins": ["EN",
   "D[0..3]"]}`; each pin gets a local label of its name on the parent, and
   the receipt names the new placement (its path is `/Driver/`). Join the
   parent's pins with `kind: "local"` labels of the pin names, the sub-sheet's
   pins (with `sheet: "/Driver/"`) with `kind: "hierarchical"`. A vector net
   such as `D[0..3]` takes one pin per member in member order, all facing one
   way, and draws the bus with an entry per pin. The same call with the name of
   a sheet already on the parent adds the pins it lacks. `file` (an existing
   sub-sheet's placement id, file id or path such as `/Driver/`) places that
   file again under the new `name`, its pins from the file's hierarchical
   labels; then `pcb_schematic_annotate` with `fill`, since its parts arrive
   unnumbered, and tools that edit that file refuse from then on.
6. `pcb_schematic_add_no_connect` with every unused pin in one call:
   `{"targets": [{"reference": "A1", "pins": ["D2", "D3", "D4"]}]}`
7. A pin is its embedded name, or its number when the part repeats that name
   (an Arduino Nano's two GND pins are `4` and `29`). An ambiguous name is
   refused with the numbers to use.
8. Use the batch's ERC counts; page `pcb_schematic_list_erc` and fix findings
   until clean before building the board.

**Board.**

1. `pcb_board_set_outline` with `rect {x, y, width, height}` or closed segments.
2. `pcb_board_sync_components` (Update PCB) with no `positions`: new
   footprints land beside the outline, as in the editor, and the receipt warns
   that they are off the board. Then `pcb_board_place_footprint` (mm) for each
   reference, or `pcb_board_autoplace` with `{"references": ["R1", "C3"]}` to
   let the editor's autoplace put them inside the outline near the copper
   they connect to (place connectors and other fixed parts yourself first).
   `pcb_board_list_footprints` reads them back. Place each IC's
   decoupling capacitor close to the supply pin it serves: the final review
   warns above 3.5 mm, or above a reviewed `layout` distance fact. Put USB and
   power connectors at the board edge.
3. `pcb_board_configure_stackup`, for example 2 copper layers and one FR4
   dielectric: export needs an explicit stackup that matches a manufacturing
   preset (Export below).
4. `pcb_board_configure_design_rules` for board minimums (`minClearanceMm` and
   the other `*Mm` fields).
5. Pour the planes first with `pcb_board_pour_copper_zone` (for example
   `GND` on `B.Cu` or an inner plane layer): routing keeps signal tracks off
   power-plane layers and out of other nets' plane fills.
6. Route the whole board, or several nets, with `pcb_board_autoroute` (no
   arguments, or `{"nets": ["SDA", "SCL"]}`; on a large board add
   `"effort": "quick"`). It routes every unrouted
   connection in scope as one undoable edit, never moves existing or locked
   copper, and reports routed/total, vias and each connection it left
   unrouted (net, `ref.pad` ends, reason). An unrouted list is an honest
   result: report it, or repair those connections one at a time. It leaves a
   differential pair's nets unrouted (`pair-pending`); never route a pair as
   two nets, route it with `pcb_board_route_pair` (Tool notes).
7. Repair or add single connections with `pcb_board_route_net`
   (`fromRef/fromPad`, `toRef/toPad`, optional `layer` and `widthMm`).
   Without `layer` or `via`, it tries every copper layer both pads share,
   then places up to two through vias itself onto another signal layer; the
   result lists them under `routing.vias`. With `layer` it stays on that
   layer. A search that stops short returns `partial`, names the layers tried
   and whether the search area or the time budget ran out, and adds nothing:
   move parts, or draw an exact path with `pcb_board_add_track`. A partial
   route refuses its batch. A net of a differential pair is refused.
8. Use the batch's DRC counts (with schematic parity when the schematic has
   parts); page `pcb_board_list_drc` and fix findings until clean.

**Save.** `pcb_design_save` waits until the sheets and the board are durably
stored and returns `saved` with both revisions, or `timed_out` / `uncertain`
with a reason. It waits for the co-editing room checkpoint or editor save and
never reports saved early. Call it in any plan or without one, without asking
for approval. It needs no plan entry and saves the current content regardless
of which held `expectedRevision` you supply. See Every call for tab revisions.

**Export.** `pcb_board_export_manufacturing` saves the design first, as
`pcb_design_save` does, then runs the final review, then stores a ZIP (Gerbers
incl. mask and silk, drill, position, BOM) as a design asset and returns
`artifact` (`assetId`, filename, SHA-256 `contentHash`, size, file list,
short-lived URL), never file bytes. The receipt names the variant: it reads
`Exported <zip> (N files, default variant).`, and export always uses the
default variant. Select the archive contents with `artifactKinds`. The approved
plan must list it and carry:

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
      { "requirementId": "drc", "selector": { "kind": "drc" }, "applicability": "required" },
      { "requirementId": "pin-1", "selector": { "kind": "pin-1" }, "applicability": "when-applicable" },
      { "requirementId": "polarity", "selector": { "kind": "polarity" }, "applicability": "when-applicable" }
    ]
  }
}
```

`manufacturingPreset` is one of two presets. Each needs an explicit stackup
with exactly its copper layers, every copper 35 µm (1 oz), FR4 dielectrics
between them, and mask rows on both sides; edge connectors, castellations and
edge plating are outside both:

- `jlcpcb-2l-fr4-1oz-green-routed-no-vcut-v1`: F.Cu and B.Cu with one FR4
  dielectric (`pcb_board_configure_stackup` with `copperLayerCount: 2`).
- `jlcpcb-4l-fr4-1oz-green-routed-no-vcut-v1`: F.Cu, In1.Cu, In2.Cu and B.Cu
  with three FR4 dielectrics (`copperLayerCount: 4`). A 0.5 oz (17.5 µm) inner
  layer fails the review.

There is no other layer count, no 2 oz preset and no castellated preset: a
board that matches neither preset cannot export. Pick the preset that matches
the board's copper, and put its stack in the `stackup` brief item's text.

ERC and DRC are required. The `pin-1` (every footprint marks pin 1 on F.Fab)
and `polarity` (a diode, LED or polarized capacitor marks its cathode or +)
checks are optional; add them for any board with ICs or polarized parts.

A save it cannot confirm refuses `SAVE_FAILED` ("Nothing was exported: the
design must save first." with the save's reason): nothing was reviewed or
uploaded. Fix what the reason names (see Results for `ROOM_CLOSED`), call
`pcb_design_save` until it answers `saved`, then export again.

Without these, export is refused with `FINAL_REVIEW_REQUIREMENTS_UNAVAILABLE`
and a copyable example: end the plan, propose one with the requirements, and
export again. A plan's requirements cannot be added after approval.

A `REVIEW_NOT_READY` refusal lists what blocks it (unmet requirements, critical
findings, what it could not verify). Fix those and export again. A review too
large to list gives counts only: page it with `pcb_board_get_final_review`
(`section` findings, requirements, unsupported, artifacts or pairs, with
`pageSize` and `cursor`; `{}` gives the summary).

Other export refusals say what to do next in their message:

- `SUPERSEDED_REVIEW`: a newer review (for example one the user started in the
  editor's review panel) replaced this one. Call the export again.
- `CANCELLED`: the review or generation was cancelled. Export again only if
  the user still wants the files.
- `GENERATION_UNAVAILABLE`: generation stopped before it finished. Export
  again once; if it fails again, ask the user to export from the editor's
  Fabrication Outputs menu.
- `STALE_ZONE_FILLS`: copper fills are out of date. Refill with
  `pcb_board_refill_copper_zone` (in a plan), then export again.

None of these issued an archive.

A successful export can still end with `Not verified; do not report a passed
review:` and a list. It carries what the review could not check and the
design-intent warnings: a decoupling capacitor too far from its supply pin, an
IC supply pin with no capacitor of its own, an I2C line with no pull-up. Fix
each one (move or add the part), check again and export again. Report a
passed review only when the list is gone; tell the user about any item you
leave and why.

## 5. Import, merge or rename

`pcb_design_import_kicad` is in the `advanced` toolbox, which starts closed:
open it first (Connect, item 7). It imports from one of two sources:

- **KiCad files:** `mode` and `files: [{path, text}]`, up to 64 files at
  project-relative paths. `mode: "replace"` replaces the design's schematic and
  board with a KiCad project; `mode: "append"` adds the project's sheets, and
  its board's items, beside this design's. It runs the same conversion as the
  editor's File menu import of a KiCad project folder, but takes modern KiCad
  text files only: `.kicad_pro`, `.kicad_sch` (including sub-sheets),
  `.kicad_pcb`, `.kicad_dru`, `fp-lib-table` and `sym-lib-table`. Legacy
  KiCad 5 files (`.pro`, `.sch`) and library files (`.kicad_sym`,
  `.kicad_mod`) are refused. Send one project with one `.kicad_pro` and its
  own files; without a `.kicad_pro` it refuses `KICAD_PROJECT_MISSING`. A
  replace without a `.kicad_pcb` replaces the schematic only and keeps the
  design's board; the dialog and the warnings say so.
- **Another design (merge):** `{"mode": "append", "fromDesignId": "..."}`
  appends that design's sheets and board items to this design. A design is only
  ever appended (`mode: "replace"` with `fromDesignId` is refused), and it
  takes no `files`. The source design must be granted to your client too
  (`pcb_designs_list`); otherwise it refuses `DESIGN_NOT_GRANTED` with the
  link where the user grants it. It cannot merge a design into itself.

**A project over 4 MiB goes in parts.** One call carries at most 4 MiB of
file text (more: `PROJECT_TOO_LARGE`). Send up to 8 calls of 4 MiB each (32
MiB in all) with the same `importId` (1 to 64 letters, digits, `_` or `-`),
`part` 1, 2, 3 … in order, and `final: false`, then the last part with
`final: true`. All three go together, with `mode` and `files`. A path sent
again in a later part continues that file's text, so a large file can be
split across parts. Each part is a write with the current schematic
`expectedRevision` and its own new `idempotencyKey`. A part before the final
one answers `staged` with what is held so far and asks nothing. The final part
asks the user and imports the whole project. A part out of order refuses
`IMPORT_PART_OUT_OF_ORDER` with the part to send next, or says to start again
at part 1. The staged parts are kept for 10 minutes after the last one, and a
new `importId` at part 1 drops an unfinished one. If the user declines or the
approval expires, the parts are kept: ask the user, then send the final part
again (after a decline, writes without a plan are refused for 30 s).

**The result.** An import answers `applied` with `receipt.summary` (for a
replace: sheets, symbols linked to the library and embedded, footprints or
"the design's board kept") and an `import` report: `project`, `sheets`,
`symbols`, `footprints`, `tracks`, `nets`, `missingFiles` (sheet files the
project names but you did not send, up to 20), `warnings` (up to 10 lines,
the last naming how many more) and `boardRevision`. `warnings` carries what
File > Open logs: weak library links, unknown pin types, power symbols with an
empty Value, oversize library tables, KiCad 6 sheets that disagree about a
symbol, a board that was not read, and a replace that kept the board. Tell the user about each warning and
missing file; a missing sheet file means part of the schematic is absent.

`IMPORT_FAILED` says which file failed and why ("Could not open <file>:
<error>"); nothing changed, so fix that file and import again.
`IMPORT_PARTLY_APPLIED` (status `uncertain`) gives the same cause: the import
stopped part-way and the design holds part of it. Read
`pcb_schematic_get_summary` for the current revision and import again with it.

Either way, every import asks the user in its own editor dialog, even inside a
plan: plans cannot pre-approve it, so call it without `planId` (with one it
refuses `PLAN_TOOL_NOT_ALLOWED`), with the usual `expectedRevision`
(schematic) and `idempotencyKey`. Undo cannot take it back. An append never
replaces anything here: ids already in the design get new ids; net classes,
their assignments, bus aliases and variants join by name, this design's
rules winning where a name is taken; ERC settings stay this design's (differing
rules are listed in the warnings); the source board's footprints, tracks and
zones land beside this board on the merged nets, without its outline or board
setup. Annotate if references repeat, sync the board, and read the schematic
and board summaries again.

**Rename.** `pcb_design_rename` with `{"name": "Dimmer rev B"}`, the
schematic `expectedRevision` and a new `idempotencyKey`. The name is saved at once and Undo cannot take
it back, so it asks the user in its own dialog unless an approved plan lists
it. It answers `saved`, or refuses `RENAME_FAILED` (read-only, changed
elsewhere, or a name the server refused).

## 6. Hand a task to the editor's agent

`pcb_task_run` gives a goal to the engineering agent in the user's Agent panel,
which works with the editor's own model and skills instead of yours. Use it
only when the user asks for that; otherwise build with the tools above. Pass
`designId`, `domainId` (`pcb-schematic` or `pcb-board`), the domain's current
`expectedRevision`, `goal` (one plain request, up to 4096 characters) and
optionally `approvedBrief` items. No plan or `catalogVersion`. It needs the
`pcb:write` scope and a grant with edits allowed, and the user must have that
design's engineering task open in the Agent panel; the editor asks the user to
agree before it edits.

One call waits up to 40 seconds. A task that ends in that time answers
`delivered` with `result` (status, new revision, pinned skill versions,
checkpoints): references and hashes, not design data, so read the design
afterwards. A task still working answers `running` with a `taskId` and, once
the editor has reported, `progress` in the same shape as `result`. `running` is
not an error and not an outcome: the editor's agent is still planning, waiting
for the user to agree (`progress.status` `awaiting_agreement`), editing or
verifying. Keep the `taskId`.

- **Poll**: call again with only `designId` and `taskId`. It waits up to 40
  seconds again and answers `running` or the final answer. Poll until the
  status is something else; do not start the task again meanwhile.
- **Cancel**: `designId`, `taskId` and `cancel: true` stop the task and answer
  `cancelled`, or the final answer if it had already ended. Stopping your own
  first call before it answers a `taskId` also cancels the task.
- The task runs while the user's editor tab is open; a tab that stops
  reporting for 150 seconds ends it as `timed_out`.
- A finished answer stays readable by its `taskId` for 10 minutes.
- The grant is checked on every call, so revoking it, or its expiry, ends
  polling: the call refuses `GRANT_REVOKED` or `GRANT_EXPIRED` and the outcome
  is not readable by `taskId` any more. Read the design once access is back.
- `refused` with `TASK_HANDLE_UNKNOWN`: the `taskId` expired, belongs to
  another client or design, or the server restarted, which ends the task. Read
  the design, then run the task again if it is still needed.

`unavailable` carries `designUrl` to open; `refused` says what the panel
needs; `busy`, `cancelled` and `timed_out` report no outcome; the editor may
have changed the design, so read it before retrying.

## 7. Results

- `applied`: the editor applied the change. `verified`: it also checked it.
  `saved`: it is durably stored. Never claim a save without a `saved` receipt.
- Inside a plan, writes answer `applied` or `verified`. Call `pcb_design_save`
  after the last edit; only it answers `saved`.
- Batches add `operations[]` and optional `checks` counts; see Batches below.
- `uncertain`: the outcome is unknown. Read again; do not resend under a new key.
- `refused` comes with a reason and usually a message with a valid
  `Example: {...}` in millimetres. A bad argument is named by its path
  (`rails[1].rail: ...`), and an insert refusal by its reference. It is a
  normal stop: read the reason, fix the call or the design, and do not
  invent other tools.
- A write the editor cannot take refuses with its own cause:
  - `WRITE_UNAVAILABLE`: your grant does not allow edits. Ask the user to
    allow edits in the design's Agent panel.
  - `READ_ONLY`: the message names the user's role on the design (such as
    `VIEWER`), which cannot edit it. Reads still work. Tell the user to ask the
    design's owner for edit access; do not retry.
  - `ROOM_CLOSED`: co-editing stopped after the tab joined, so nothing made now
    would be saved. Ask the user to reload the tab (or keep its edits with
    File > Save Project as `.dtxpro`), then read again before writing.
  - `DECLINE_COOLDOWN`: the user declined a write here, so writes without a
    plan are refused for the seconds the message gives. Ask the user what they
    want, or propose a plan; do not resend.
  - `INVALID_IDEMPOTENCY_KEY`: `idempotencyKey` must be a UUID, a new one per
    write.
  - `STALE_REVISION`: the message says the design changed (or that a
    collaborator changed it in the co-editing room) and gives its current
    revision. Read what you need again, then send the call with that
    `expectedRevision` and a new `idempotencyKey`.
- In a shared co-editing room, a collaborator's edits no longer stop your
  step: a write answers at the room's verdict, even if peers edit meanwhile,
  and `ROOM_REJECTED` means the room refused it and took it back out (read the
  current revision, then send it again). Only your next write's
  `expectedRevision` must be current; `STALE_REVISION` gives it.
- Report what you built from read-backs (ERC, DRC, nets, footprints), not from
  your own plan.

## 8. Tool notes

These notes supplement the build order above. Use Every call for units,
admission and revisions, and Observe, then one plan for paging and approval.

### Batches

`pcb_batch_write` takes `{ operations: [{ tool, args }], check }` plus the
usual write envelope. Use 1 to 100 ordered operations on one document: all
schematic or all board. Each `args` is exactly the single tool's arguments,
in millimetres. Later operations see earlier changes. A batch is all or nothing,
in one transaction with one undo entry.

An approved plan is required (`PLAN_REQUIRED`). Each operation spends one plan
call; the batch costs no extra call. `PLAN_EXHAUSTED` says how many calls are
needed and left. A batch refused in the editor has spent its calls.

`pcb_design_save`, `pcb_board_export_manufacturing`, `pcb_design_import_kicad`,
plan tools and the batch itself cannot be operations (`BATCH_TOOL_NOT_ALLOWED`).
An operation may name a tool of a closed toolbox, such as
`pcb_board_route_pair` or `pcb_board_tune_pair` while `advanced` is closed.
Mixing schematic and board tools gives `BATCH_MIXED_DOMAINS`. Copper-zone
tools (pour, refill) go in a batch of their own: mixing them with other tools
is refused before anything runs (`BATCH_MIXED_ZONE_TOOLS`).

Results have `operations[]` with zero-based `index`, `tool`, `status` (`applied`
or `noop`) and `summary`. With `check: true`, `checks.erc` has `errors` and
`warnings`, or `checks.drc` has `errors`, `warnings` and `unconnected` for a board.
If all operations are `noop`, the batch is refused with `NO_CHANGE`.
Non-zero counts do not undo the commit; page the read tools for findings.
The receipt's `revision` is the next `expectedRevision`.

On refusal, `operation.index` is the zero-based operation that failed, with that
tool's own message. Fix it and resend the WHOLE batch: nothing was applied.
Whole-call refusals may have no `operation`. For `REQUEST_EXPIRED`
("after staging K of N"), resend as smaller batches.

### Read the design

- `pcb_schematic_get_summary`: The first 16 sheet placements include
  `sheetInstanceId` and path. Inserts use those IDs as described above. ERC
  violations are a bounded page.
- `pcb_schematic_list_symbols`: References are the displayed symbol references.
  Scope selectors by sheet, reference or connected net. See the observation
  advice above for fields and page size.
- `pcb_schematic_get_symbol`: UUIDs are not references. A reference names the
  whole part on one sheet placement: the result lists `units[]` (unit, id,
  position, rotation) and the pins of every unit. `pin` filters by pin number
  or name. A reference on several sheet placements needs `sheetInstanceId`.
- `pcb_schematic_get_net`: Address an unnamed net with its solver identifier.
  Pin endpoints are semantic and paged; `detailed` adds each pin's electrical
  type.
- `pcb_schematic_list_erc`: Download the full ERC report from the ERC panel.
- `pcb_board_get_summary`: Counts include current DRC findings, with a bounded
  violation page. `severity` and `reference` narrow the page, never the counts
  (the same holds for the schematic summary's ERC counts and
  `pcb_board_run_drc`).
- `pcb_board_list_footprints`: Listing references does not derive DRC or load
  geometry. See the observation advice above for fields and page size.
- `pcb_board_get_footprint`: Returns separate geometry boxes and bounded pads,
  never footprint primitives.
- `pcb_board_get_net`: Reports routed length and pages the net's tracks and
  vias under `tracks` (`id`, `kind`, layer or layers, width or diameter and
  drill, ends or position) with `cursor`. Pad endpoints (`padCursor`) and
  ratsnest endpoints (`ratsnestCursor`) are paged separately.
- `pcb_board_get_region`: Lists the footprints and the board's own tracks,
  vias, zones and graphics in the region, each with `id`, `kind` and layers.
  Intersection uses placed geometry bounds, rather than footprint origins
  alone.
- `pcb_board_list_drc`: Uses the editor's DRC runner.
- `pcb_board_get_stackup`: Read back the physical stackup before editing,
  including materials and dielectric properties.
- `pcb_board_get_net_classes`: Dimensional class fields carry their source
  `Mm` suffix. A board net's `effective.sizes` are the track width, clearance
  and via drill and diameter after board minimums and approved fab floors.
- `pcb_board_get_mechanical`: Heights are model-bounds hints or explicitly
  unavailable. Results contain no meshes or model IR.

### Approve the work

- `pcb_plan_propose`: See Observe, then one plan for fields and approval.
  Requirement-gated tools read `requirements` as approved facts and check them
  against the design when used. `requirements` takes only `brief` and
  `finalReview`; any other key is refused by name.
  - `requirements.brief`: Final-review check IDs must cite brief items with
    category `user_decision`, provenance `user` and approval `approved`. The
    user approves them with the plan. See the Export example for a `stackup`
    item whose `value {referencePlane: {net, layer}}` names the reference
    ground.
  - `requirements.finalReview`: Required for manufacturing export; list that
    tool in a step. Checks cite approved brief items and are evaluated against
    the board. `artifactKinds` selects archive contents: drill is always
    included; add gerber, bom and placement as needed. Functional selectors
    also require `reference` and `functionalKind`.

    ```text
    Minimal: {manufacturingPreset, artifactKinds: [gerber, drill, bom, placement], checks: [{requirementId: erc, selector: {kind: erc}, applicability: required}, {requirementId: drc, selector: {kind: drc}, applicability: required}]}.
    ```

- `pcb_plan_get`: Status is `pending`, `approved`, `declined`, `stopped`,
  `expired` or `exhausted`. Omit `planId` to read this client's latest plan for
  the design. `waitSeconds` holds a pending call for up to 30 seconds and
  answers immediately on approval or decline. See Observe, then one plan for
  the wait loop.
- `pcb_plan_end`: See Observe, then one plan for when to end it and undo.

### Choose parts

- `pcb_components_search` and `pcb_components_inspect`: Search by part kind
  (resistor, potentiometer, LED, connector), part name, MPN or manufacturer;
  value words such as 10k or 220 are ignored; supply value in
  pcb_schematic_insert_components, or edit it later with
  pcb_schematic_set_symbol_field. Then inspect a returned componentId; the
  catalog's default symbol and footprint are selected unless you pass their
  IDs. A result with packageCount 0 is a generic symbol: insert it with a
  footprint from pcb_footprints_search that its footprintFilters describe.
  Example:

  ```text
  {componentId: <returned ID>, pinNumber: '1'}
  ```

  For `pcb_components_search`, continue with `nextOffset` and the same
  query/limit. Pages are best effort because the catalog API has no collection
  revision. For `pcb_components_inspect`, pin labels and datasheet links are
  not manufacturer evidence.
- `pcb_footprints_search`: Searches name substrings, optionally within a
  library. Name examples: `LED_D5.0mm`, `3386`, `PinHeader_1x05`. Library
  examples: `LED_THT`, `Resistor_THT`, `Potentiometer_THT`,
  `Connector_PinHeader_2.54mm`. Returned `Library:Name` values also work in the
  Footprint field.

  ```text
  {"query":"LED_D5.0mm","library":"LED_THT"} or {"query":"PinHeader_1x05_P2.54mm"}
  ```

- `pcb_part_define`: See Parts above for symbol geometry, grid, `pinToPad` and
  ID format. Footprints have pads with size and optional drill, a courtyard
  rectangle, optional `fab` and `silk` outlines and silk text, and `smd` or
  `through_hole` technology. Omit `fab` for the default bevelled F.Fab outline;
  always add a silk outline clear of the pads (Parts above). Both symbol and
  footprint checkers validate the part. It is stored only in the design, never
  a library. See Parts above for refusals and their fixes, `replace: true`,
  `remove: true` and the `preview`. `variantOf` (an existing inline part's ID,
  with `name` and `footprint` but no `symbol` or `pinToPad`) adds another
  footprint for the same pins, usable in the Footprint field. Pass its ID as
  `inlinePartId` on insert, with optional `value`.
- `pcb_part_get`: Omit `inlinePartId` to list every inline part's ID, name,
  pin count, pad count and footprint names; with it, read the whole stored
  definition in mm (the starting point for a `replace: true`).

### Draw the schematic

For embedded pin names and repeated names, see Schematic step 6. For list
limits, atomicity and skipped-pin counts, see Schematic step 2. Lists need at
least one target; labels and rails need at least one entry. Each target needs
1..64 unique pins. The upper limits above apply to all three list tools.

- `pcb_schematic_insert_components`: Each component names exactly one of
  `decisionId` and `inlinePartId`. Decisions must be explicitly host-reviewed;
  inline IDs come from `pcb_part_define`. For a generic library symbol, use
  the catalog guidance above; its required `Library:Name` footprint must have
  pads covering its pins. Every reference is explicit. Optional `value` sets
  Value on every unit in the same undo entry; any string up to 1024 characters
  is accepted, including empty text. Positions are optional, one per unit, on
  the schematic grid from Every call:

  ```text
  { unit: 1, x: 25.4, y: 12.7, rotation: 0 }
  ```

  Alternatively, `near { reference, side }` places every unit in the first
  free 100 mil slot on that side of a placed part. Omit both to select the
  next free slot to the right of the sheet's parts. Raw geometry and
  manufacturer claims are not accepted.
- `pcb_schematic_connect`: Connects exactly two actual embedded pins on one
  unique sheet placement. Code resolves native geometry. Cross-sheet,
  repeated-file, a path that meets a bus and unintended joins refuse; a join
  of two named nets refuses naming both.
- `pcb_schematic_add_label`: List form:

  ```text
  labels [{net, kind, targets: [{reference, pins, sheet?}]}]
  ```

  Kind is `local`, `global` or `hierarchical`. Labels go on the connection
  point or a 2.54 mm stub wire when that point is taken. A bus net
  (`D[0..3]`) takes exactly one pin per member, in order, all facing one way:
  a stub per pin ends on one bus beside them (that end is the bus entry), with
  member labels and the bus label of that kind. A label entry's `members`
  defines its net as a bus alias of those members. Matching-net pins use the
  skip rule above. Missing pins, conflicting net names and unintended joins
  refuse.

  `aliases` edits existing bus aliases and runs before `labels`, which may
  then be omitted. Each entry is `{name}` plus exactly one of `to` (rename:
  every label, sheet pin and alias that refers to it follows), `members`
  (redefine) or `delete: true`. Names are plain, not vectors:

  ```text
  {"aliases": [{"name": "USB", "to": "USB2"}, {"name": "HOST", "delete": true}]}
  ```

  A rename to a name already used as an alias or net, or one that would move
  any pin to another net, refuses; so do an alias that names itself and
  deleting an alias something still refers to.
- `pcb_schematic_add_sheet`: `{name, pins?, sheet?, file?}`. A hierarchical
  sub-sheet under `sheet` (default the root), its box placed by code, one
  sheet pin per name (bus names allowed), each labelled locally on the parent
  (a bus pin on a short bus stub). An existing `name` with `pins` adds the
  missing pins; `file` places an existing sub-sheet again (Schematic step 5).
  A parent whose file is placed more than once, a taken name without `pins`,
  or a `file` that names no single sub-sheet refuses.
- `pcb_schematic_add_power`: List form:

  ```text
  rails [{rail, targets: [{reference, pins, sheet?}]}]
  ```

  Code places each power symbol outward from the pin and wires it.
  Matching-rail pins use the skip rule above. The PWR_FLAG rule in Schematic
  step 3 checks for a power output anywhere in the design. Conflicting net
  names refuse.
- `pcb_schematic_add_no_connect`: List form:

  ```text
  targets [{reference, pins, sheet?}]
  ```

  Flags go on connection points. Already marked pins use the skip rule above.
  Missing or connected pins refuse.
- `pcb_schematic_add_wire`: Explicit points contain 2..64 sheet coordinates
  on the connection grid from Every call and are never rounded. Named
  `from`/`to` pins produce an orthogonal path. Code adds junctions where the
  wire tees into another wire. A wire that would join two named nets refuses
  and names them, as does a points wire onto a no-connect pin; a wire within
  one net applies.
- `pcb_schematic_move_symbol`: Addresses an unwired symbol by reference.
  Move all units or one unit by direction and a number of 2.54 mm steps; code
  computes the grid position. Broken or joined connections, body overlap and
  leaving the pin grid refuse.
- `pcb_schematic_rotate_symbol`: Rotate all units or one unit of an unwired
  symbol by a quarter turn clockwise, counterclockwise, or a half turn about
  its origin. Broken or joined connections, body overlaps and off-grid pins
  refuse.
- `pcb_schematic_remove_symbol`: Removes every unit and pin labels/no-connect
  flags serving no other wire or pin. Wires stay. Move, rotate and remove
  refuse a reference two parts share: annotate `duplicates` first.
- `pcb_schematic_annotate`: `fill` numbers unannotated parts; `duplicates`
  renumbers the later part of each duplicate reference; `all` renumbers every
  part by position.
- `pcb_schematic_tidy`: Autoplaces symbol fields and orients every label
  along its wire on one `sheet`; `layout: true` also arranges the parts in
  blocks. The net-to-pin map must remain identical.
- `pcb_schematic_set_symbol_field`: See Schematic step 1 for Value, Footprint
  and Datasheet; user fields are supported too. It sets every unit of the part
  in one undo entry. `field: "Reference"` refuses: use
  `pcb_schematic_annotate`.
  Footprints must resolve to library land patterns or patterns embedded in
  the design. Ambiguous references require a sheet path or sheet ID.
- `pcb_schematic_set_net_class`: Creates or updates a project class by name
  and optionally assigns named nets. Default is used by every unassigned net.
  Dimensions include track width, clearance and via sizes. The board router
  and DRC consume these classes.

### Build and check the board

- `pcb_board_set_outline`: Replaces all board-owned Edge.Cuts, including
  cutouts. The rectangle form in Board step 1 also accepts `cornerRadius?`.
  Paths contain line segments or arcs through `mid`. Mounting holes are
  footprints, not outline geometry.
- `pcb_board_sync_components`: Uses the editor's Update PCB operation from
  Board step 2. Adds new footprints and updates changed ones while keeping
  existing footprints, routes and user models. `removeMissing` removes
  unlocked footprints whose symbols disappeared; board-only footprints stay.
  Courtyard/edge findings appear as receipt warnings. `reloadFootprints`
  (1 to 64 board references, sent on its own with no other argument) is the
  Tools menu's Reload Footprints from Library for those parts, one undo: an
  inline part's footprint is read from the design, so this brings a repaired
  part (`replace: true`) onto the board. The receipt lists the parts reloaded,
  already matching and not found in the library, and names other references
  that use the same footprint (reload them too if they need it). Run
  `pcb_board_run_drc` afterwards: reloaded pads can meet tracks differently.
- `pcb_board_place_footprint`: Positions are absolute; rotation is degrees.
  Courtyard overlaps and courtyards crossing the edge are applied and reported
  as receipt warnings.
- `pcb_board_autoplace`: `{"references": [...]}` (1 to 200). The editor's
  autoplace: each part moves to the free spot inside the board outline
  nearest the copper it connects to, keeping its rotation and side; a part
  with no room stays where it is and the receipt names it. One undo for the
  whole call. It needs a closed outline on Edge.Cuts; an unknown, shared or
  locked reference is refused before anything moves. Approved placement facts
  are honoured, and a result that breaks them is refused with the board
  unchanged; an MCP plan carries no placement facts, so over MCP placement
  findings come back as receipt warnings, as for `pcb_board_place_footprint`.
- `pcb_board_move_footprint`: Movement is relative to the footprint's current
  position.
- `pcb_board_delete_items`: Accepts footprint `references` and `ids` of
  tracks, vias, zones or board graphics as `pcb_board_get_net` and
  `pcb_board_get_region` return them. At most 200 items per call; no
  delete-all. Locked and unknown items refuse.
- `pcb_board_configure_stackup`: Dielectric ply 0 is the row; higher indices
  identify existing sublayers. Changing copper count preserves thickness.
  Explicit ply thickness edits update board total thickness. Material
  properties are supplied facts, not verified impedance. See Board step 3 for
  the export stackups (two presets, 2 or 4 copper layers).
- `pcb_board_configure_design_rules`: Changes board-wide Board Setup minimums
  while preserving other settings. It does not edit project net classes or
  establish supplier compliance. Zero disables a minimum; null restores its
  existing default. `minResolvedSpokes` is an integer count.
- `pcb_board_autoroute`: The editor's autorouter over the same router and
  DRC as `pcb_board_route_net`: one pass in net order, then rip-up and retry
  passes; every connection whose copper adds a DRC marker is withdrawn
  (reason `drc`). Reasons: `blocked`, `budget`, `drc`, `pair-pending`,
  `cancelled`. `effort`: `"quick"` is the single pass, `"normal"` (the
  default) adds up to 7 rip-up passes, `"thorough"` up to 29 and is the
  slowest. It routes before asking, so the approval names the result; a
  call past the 90 s write window answers `timed_out` and adds nothing. On a
  large board (hundreds of connections) use `"quick"`, and route in parts
  with `nets` if quick still times out; then repair what is left with
  `pcb_board_route_net`, or try `"normal"` on the nets left unrouted. Its
  own call: never a `pcb_batch_write` operation. Crossed pours refill in the
  same transaction.
- `pcb_board_route_net`: The editor's router, one 200 ms search budget per
  try, and the result must pass native DRC. Without `layer` or `via` it tries
  each copper layer both pads share, then through vias onto each other signal
  layer, at most two per route (Board step 7); their size is the net class's
  via raised to the board and fab minimums, and they never touch a pad or
  land on a power-plane layer. `via` (`toLayer`, `type: "through"`, optional
  `anchor` at a track end or an existing through via, `diameterMm`,
  `drillMm`) asks for one explicit layer change. Blind and micro vias, `mode:
  "push"` and nets of a differential pair are refused. A track on an inner
  power-plane layer, or one that would cut another net's plane fill, is
  refused with the layer named and the signal layers to use. Crossed pours
  refill in the same transaction. A partial search returns the last clear
  point and adds no copper; pads with no common layer that no router via
  could join refuse with the tries listed. Geometry compliance does not
  establish engineering readiness: current-budget provenance and reference
  continuity require evidence.
- `pcb_board_route_pair` (`advanced` toolbox, or a batch operation): routes a
  differential pair's two nets between named pads as one coupled route, its
  width and gap from the net class, the tuning profile or
  `targetImpedanceOhms` (on the stored stackup). Every length is in mm:

  ```json
  {"positiveNet": "USB_D+", "negativeNet": "USB_D-",
   "from": {"positive": {"reference": "J1", "pad": "2"}, "negative": {"reference": "J1", "pad": "3"}},
   "to": {"positive": {"reference": "U1", "pad": "1"}, "negative": {"reference": "U1", "pad": "2"}},
   "allowedLayers": ["F.Cu"], "layer": "F.Cu", "maxVias": 0,
   "maxLengthMm": 50, "maxSkewMm": 0.15, "targetImpedanceOhms": 90}
  ```

  `maxVias` is even (0 to 32). At most one paired layer change (`endLayer`),
  through vias only, with its return via (`returnViaId`) already within 1 mm;
  there is no pair autorouter. Take `maxLengthMm`, `maxSkewMm`,
  `minForeignSeparationMm` and the impedance target from the approved brief:
  a limit you pass only tightens the route, it is not an approved
  requirement, and an absent one, like signal integrity, stays unverified.
  A refusal keeps the prior copper, and its message carries `residuals`:
  each missed constraint with its actual, required and residual value in mm.
- `pcb_board_tune_pair` (`advanced` toolbox, or a batch operation): the same
  pair fields (no `layer`), plus `trackId` (a track of the routed pair, from
  `pcb_board_get_net`), `mode` `"length"` or `"skew"` (positive minus
  negative) and `targetMm`, with optional `maxAmplitudeMm`. It adds meanders
  within the design rules and tuning settings; the amplitude cap only
  tightens them. A refusal keeps the prior copper and carries `residuals` the
  same way.
- `pcb_board_add_track`: Adds an exact path on a copper layer, optionally
  with full-stack through vias at specified points. It performs no search and
  has no DRC gate. Shorts refuse before commit and name the other net. Crossed
  pours refill in the same transaction. Run `pcb_board_run_drc` afterward.
- `pcb_board_pour_copper_zone`: Creates or reshapes a plane to the native
  closed outline and refills it. Resizing requires a single exterior outline
  and a single-layer zone. Refill also covers other stale pours required for
  consistent clearances.
- `pcb_board_refill_copper_zone`: Does not change the selected zone's outline.
  It also refills other stale pours as described above. Run after routing and
  before DRC.
- `pcb_board_run_drc`: Runs against the current board revision. Returns
  error, warning and unconnected counts by rule and the first findings page.
  Continue with `pcb_board_list_drc` and the returned cursor. The run never
  edits; refill pours first. See Board step 8 for schematic parity.

### Designs, save, export and import

- `pcb_design_save`: See Save for durable checkpoints and approval, and Every
  call for revision tokens across tabs and sessions.
- `pcb_board_export_manufacturing`: See Export for the save it makes first,
  the presets, required plan facts, refusals and returned archive metadata; see Approve the work for final-review
  selectors and artifact selection, and Board step 3 for the explicit stackup.
- `pcb_design_import_kicad` (`advanced` toolbox): See Import, merge or rename for its two sources
  (KiCad files, or another design to merge), the accepted files, sending in
  parts, the `import` report, failures and separate editor approval.
- `pcb_design_rename`: See Import, merge or rename.
- `pcb_designs_list`, `pcb_design_create`, `pcb_design_open`: See Connect.
- `pcb_task_run`: See Hand a task to the editor's agent.
