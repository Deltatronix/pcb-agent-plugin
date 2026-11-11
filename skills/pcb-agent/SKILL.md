---
name: pcb-agent
description: Inspect a Deltatronix PCB board, footprints, or nets and request an agreed footprint move through the connected PCB editor. Use for Deltatronix board inspection or footprint movement.
---

# PCB agent

1. Ask the user to open the requested design's PCB editor tab, enable a design
   grant for the native client's exact client ID in the Agent panel, and start
   the runner. Authenticate through the client's native connection UI and the
   Deltatronix browser consent page. Never ask for API keys, passwords, or tokens
   in chat. Reads require sign-in too. An edit needs `pcb:read pcb:write` scopes
   and an edit-enabled design grant.
2. Start every task with a current observation using `pcb_board_get_summary`.
   Inspect relevant components with `pcb_board_list_footprints` and
   `pcb_board_get_footprint`, and connections with `pcb_board_get_net`. Use the
   requested `designId`, `catalogVersion: 1`, bounded pages, and returned cursors.
   These are the four available read tools; use their current results rather
   than remembered board state.
3. Describe a scoped plan in words and wait for the user's agreement before
   edits. There is no plan, routing, or delete tool. Leave engineering decisions
   to the applicable specialist skills; this skill governs the connection and
   approval workflow only.
4. The only edit is `pcb_board_move_footprint`. Supply the current observation's
   revision as `expectedRevision`, `catalogVersion: 1`, and a new UUID
   `idempotencyKey`, together with the design, footprint reference, direction,
   and distance in nanometres (`distanceNm`). The user must explicitly approve
   the move in the browser PCB tab. Agreement in chat does not replace that
   approval. Reuse a key only for an identical retry; a changed request needs a
   new key, a fresh observation, and fresh browser approval.
5. Treat unavailable runners, refused placement, blocked routes, conflicts, and
   timeouts as normal stop results. Explain the returned reason and stop rather
   than forcing the action or inventing another tool. For an unavailable runner,
   ask the user to open the design in the PCB editor and enable its grant/runner.
6. Report the returned receipt accurately: `applied` confirms the editor applied
   the change, `verified` confirms verification, and `saved` confirms persistence.
   Never claim a save without a `saved` receipt. An `uncertain` result means the
   outcome is unknown; do not replay the move under a new key. Inspect again with
   the read tools to establish current
   state, and inspect again after a completed move before proposing more work.
