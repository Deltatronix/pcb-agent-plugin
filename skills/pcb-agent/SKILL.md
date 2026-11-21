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
   `pcb_footprints_*`) sit in the `board`, `schematic` and `parts` toolboxes;
   plan, design (`pcb_design_*`, `pcb_designs_list`), task and batch tools are
   always listed. All toolboxes start open. If a
   `pcb_*` tool you need is missing from your tools, call `list_toolboxes`, then
   `close_toolbox` the ones this task does not need and `open_toolbox` the one it
   does. The choice is kept for your client; a client that does not refresh its
   list on `notifications/tools/list_changed` shows it in its next session.

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
2. Propose one plan with `pcb_plan_propose`: a `title`, `steps`
   (`{summary, tools[]}` the user reads), `maxCalls` (one per batch operation
   plus other planned writes, up to 500), `expiresInMinutes` (up to 120),
   `expectedRevision`, and for export the `requirements` below. Use the revision
   you planned against.
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
   its rules. `pcb_plan_get` lists the same pinned versions under
   `plan.skills`; they do not change during the plan.
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
with `pcb_part_define`: symbol body and pins in mm on the 2.54 mm grid (+y
down, x/y is the pin's connection point), footprint pads in millimetres with drill for
through-hole, a courtyard, and `pinToPad`. Its id is
`inline:<name in lowercase, non-alphanumerics as ->`.

**Schematic.**

1. `pcb_schematic_insert_components`: references, `sheetInstanceId` from the
   summary, `inlinePartId` or `decisionId`, positions, and each part's `value`
   (`"10k"`, `"220R"`), set on insert. Leave room: a wire between two pins must
   not cross a third pin. `pcb_schematic_set_symbol_field` changes a Value
   later (and Footprint, Datasheet).
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
   reference. `pcb_board_list_footprints` reads them back.
3. `pcb_board_configure_stackup`, for example 2 copper layers and one FR4
   dielectric: export needs an explicit stackup.
4. `pcb_board_configure_design_rules` for board minimums (`minClearanceMm` and
   the other `*Mm` fields).
5. Route each connection with `pcb_board_route_net` (`fromRef/fromPad`,
   `toRef/toPad`, `layer`, `widthMm`). Use the other layer where routes cross. A
   search that stops short returns `partial` and adds nothing: change the layer
   or placement, or draw an exact path with `pcb_board_add_track`. A partial
   route refuses its batch.
6. `pcb_board_pour_copper_zone` (for example `GND` on `B.Cu`).
7. Use the batch's DRC counts (with schematic parity when the schematic has
   parts); page `pcb_board_list_drc` and fix findings until clean.

**Save.** `pcb_design_save` waits until the sheets and the board are durably
stored and returns `saved` with both revisions, or `timed_out` / `uncertain`
with a reason. It waits for the co-editing room checkpoint or editor save and
never reports saved early. Call it in any plan or without one, without asking
for approval. It needs no plan entry and saves the current content regardless
of which held `expectedRevision` you supply. See Every call for tab revisions.

**Export.** `pcb_board_export_manufacturing` runs the final review, then stores a
ZIP (Gerbers incl. mask and silk, drill, position, BOM) as a design asset and
returns `artifact` (`assetId`, filename, SHA-256 `contentHash`, size, file list,
short-lived URL), never file bytes. Select the archive contents with
`artifactKinds`. The approved plan must list it and carry:

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

Without these, export is refused with `FINAL_REVIEW_REQUIREMENTS_UNAVAILABLE`
and a copyable example: end the plan, propose one with the requirements, and
export again. A plan's requirements cannot be added after approval.

A `REVIEW_NOT_READY` refusal lists what blocks it (unmet requirements, critical
findings, what it could not verify). Fix those and export again.

## 5. Import, merge or rename

`pcb_design_import_kicad` with `mode: "replace"` and `files: [{path, text}]`
replaces the design's schematic and board with a KiCad project (`.kicad_pro`,
`.kicad_sch` including sub-sheets, `.kicad_pcb`, `.kicad_dru`, `fp-lib-table`,
and `sym-lib-table`; 4 MiB in all). Use project-relative paths. This matches
File > Open KiCad Project Folder and returns an import summary and new
schematic/board revisions. Every import receives separate editor approval;
plans cannot pre-approve it. Call it without `planId`.

**Merge another design.** `pcb_design_merge` with `{"fromDesignId": "..."}`
appends that design's sheets to this design's schematic. It never replaces
anything here, and the board is not changed (sync it afterwards if the parts
belong on it). Like an import it always asks the user in its own dialog,
even inside a plan: call it without `planId` (with one it refuses
`PLAN_TOOL_NOT_ALLOWED`), with the usual `expectedRevision` (schematic) and
`idempotencyKey`. Undo cannot take it back. The source design must be granted
to your client too (`pcb_designs_list`); otherwise it refuses
`DESIGN_NOT_GRANTED` with the link where the user grants it. It cannot merge a
design into itself. Read the schematic summary again afterwards.

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
- `refused` comes with a reason and usually a message with a valid example. It
  is a normal stop: read the reason, fix the call or the design, and do not
  invent other tools. `STALE_REVISION` means read again first.
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
- `pcb_schematic_get_symbol`: UUIDs are not references. Duplicate displayed
  references require a sheet placement.
- `pcb_schematic_get_net`: Address an unnamed net with its solver identifier.
  Pin endpoints are semantic and paged.
- `pcb_schematic_list_erc`: Download the full ERC report from the ERC panel.
- `pcb_board_get_summary`: Counts include current DRC findings, with a bounded
  violation page.
- `pcb_board_list_footprints`: Listing references does not derive DRC or load
  geometry. See the observation advice above for fields and page size.
- `pcb_board_get_footprint`: Returns separate geometry boxes and bounded pads,
  never footprint primitives.
- `pcb_board_get_net`: Reports routed length and segments. Pad endpoints and
  ratsnest endpoints are independently paged.
- `pcb_board_get_region`: Intersection uses placed geometry bounds, rather
  than footprint origins alone.
- `pcb_board_list_drc`: Uses the editor's DRC runner.
- `pcb_board_get_stackup`: Read back the physical stackup before editing,
  including materials and dielectric properties.
- `pcb_board_get_net_classes`: Dimensional class fields carry their source
  `Mm` suffix.
- `pcb_board_get_mechanical`: Heights are model-bounds hints or explicitly
  unavailable. Results contain no meshes or model IR.

### Approve the work

- `pcb_plan_propose`: See Observe, then one plan for fields and approval.
  Requirement-gated tools read `requirements` as approved facts and check them
  against the design when used.
  - `requirements.brief`: Placement and final-review requirement IDs must cite
    brief items with category `user_decision`, provenance `user` and approval
    `approved`. The user approves them with the plan. See the Export example
    for a `stackup` item whose `value {referencePlane: {net, layer}}` names the
    reference ground.
  - `requirements.inputArtifacts`: Identify artifacts bound by placement facts,
    such as the saved schematic.
  - `requirements.placement`: Version 1 constraints cover layers, stackup,
    fixed positions, allowed sides/rotations, relationships and mechanical
    outline.
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
  rectangle, optional silk outline and text, and `smd` or `through_hole`
  technology. Both symbol and footprint checkers validate the part. It is
  stored only in the design, never a library. Names producing an occupied ID
  are refused. Pass its ID as `inlinePartId` on insert, with optional `value`.
- `pcb_part_get`: Omit `inlinePartId` to list every inline part's ID, name,
  pin count and pad count.

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
  repeated-file, a path that meets a bus and unintended joins refuse.
- `pcb_schematic_add_label`: List form:

  ```text
  labels [{net, kind, targets: [{reference, pins, sheet?}]}]
  ```

  Kind is `local`, `global` or `hierarchical`. Labels go on the connection
  point or a 2.54 mm stub wire when that point is taken. A bus net
  (`D[0..3]`) takes exactly one pin per member, in order, all facing one way:
  a stub per pin ends on one bus beside them (that end is the bus entry), with
  member labels and the bus label of that kind. Matching-net pins use the skip
  rule above. Missing pins, conflicting net names and unintended joins refuse.
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
  wire tees into another wire and refuses unintended joins.
- `pcb_schematic_move_symbol`: Addresses an unwired symbol by reference.
  Move all units or one unit by direction and a number of 2.54 mm steps; code
  computes the grid position. Broken or joined connections, body overlap and
  leaving the pin grid refuse.
- `pcb_schematic_rotate_symbol`: Rotate all units or one unit of an unwired
  symbol by a quarter turn clockwise, counterclockwise, or a half turn about
  its origin. Broken or joined connections and body overlaps refuse.
- `pcb_schematic_remove_symbol`: Removes every unit and pin labels/no-connect
  flags serving no other wire or pin. Wires stay.
- `pcb_schematic_annotate`: `fill` numbers unannotated parts; `duplicates`
  renumbers the later part of each duplicate reference; `all` renumbers every
  part by position.
- `pcb_schematic_tidy`: Autoplaces symbol fields and faces local labels along
  their wire on one sheet placement. The net-to-pin map must remain identical.
- `pcb_schematic_set_symbol_field`: See Schematic step 1 for Value, Footprint
  and Datasheet; user fields are supported too. Reference uses annotation.
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
  Courtyard/edge findings appear as receipt warnings. With approved placement
  facts, every added reference requires an explicit in-scope position, the
  mechanical layout is applied, and new violations refuse.
- `pcb_board_place_footprint`: Positions are absolute; rotation is degrees.
  Courtyard overlaps and courtyards crossing the edge are applied and reported
  as receipt warnings.
- `pcb_board_move_footprint`: Movement is relative to the footprint's current
  position.
- `pcb_board_delete_items`: Accepts footprint references and returned IDs for
  tracks, vias, zones or board graphics. At most 200 items per call; no
  delete-all. Locked and unknown items refuse.
- `pcb_board_configure_stackup`: Dielectric ply 0 is the row; higher indices
  identify existing sublayers. Changing copper count preserves thickness.
  Explicit ply thickness edits update board total thickness. Material
  properties are supplied facts, not verified impedance. See Board step 3 for
  the explicit 2-layer FR4 export stackup.
- `pcb_board_configure_design_rules`: Changes board-wide Board Setup minimums
  while preserving other settings. It does not edit project net classes or
  establish supplier compliance. Zero disables a minimum; null restores its
  existing default. `minResolvedSpokes` is an integer count.
- `pcb_board_route_net`: Uses `search.ts`. An explicit track-end or existing
  through-via anchor supports a bounded layer transition; through vias span
  the full stack. Both legs must reach within one 200 ms search budget and
  pass native DRC. Crossed pours refill in the same transaction. A partial
  search returns the last clear point; see Board step 5 for recovery and the
  no-copper result. Geometry compliance does not establish engineering
  readiness: current-budget provenance and reference continuity require
  evidence.
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
  edits; refill pours first. See Board step 7 for schematic parity.

### Designs, save, export and import

- `pcb_design_save`: See Save for durable checkpoints and approval, and Every
  call for revision tokens across tabs and sessions.
- `pcb_board_export_manufacturing`: See Export for required plan facts,
  refusals and returned archive metadata; see Approve the work for final-review
  selectors and artifact selection, and Board step 3 for the explicit stackup.
- `pcb_design_import_kicad`: See Import, merge or rename for files, size
  limits, results and separate editor approval.
- `pcb_design_merge`, `pcb_design_rename`: See Import, merge or rename.
- `pcb_designs_list`, `pcb_design_create`, `pcb_design_open`: See Connect.
- `pcb_task_run`: See Hand a task to the editor's agent.
