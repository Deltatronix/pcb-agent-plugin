# Deltatronix PCB agent

A Claude Code and Codex plugin for [Deltatronix PCB](https://pcb.deltatronix.io). It lets your
coding agent inspect a board that is open in the Deltatronix PCB editor and request a footprint
move that you approve in the editor. It uses your Deltatronix account for PCB access and your
client's own model for reasoning.

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
   and approve the consent page.
2. Open the design in the PCB editor, open the Agent panel, create a design grant for the client
   ID shown at consent, and start the runner.
3. Ask the agent to inspect the board. Moves need the `pcb:read pcb:write` scopes, an
   edit-enabled grant, agreement on the plan, and your approval in the browser PCB tab.

Never paste API keys, passwords or tokens into chat. Every tool needs OAuth sign-in, reads
included; platform cookies do not authenticate MCP calls.

Other clients that support remote MCP servers with OAuth (Claude Desktop, ChatGPT custom
connectors) can use the same server URL: `https://api.deltatronix.io/mcp`.

## What it can do

- Read: `pcb_board_get_summary`, `pcb_board_list_footprints`, `pcb_board_get_footprint`,
  `pcb_board_get_net`.
- Edit: `pcb_board_move_footprint`, the only edit. Routing and deletion are not exposed.

Start with a current observation. Each move uses its revision, catalog version 1 and a new UUID
idempotency key; reuse a key only for an identical retry. An `applied` receipt confirms the editor
applied the change, `verified` confirms verification, and only `saved` confirms it was saved. An
`uncertain` result has an unknown outcome: inspect again and do not resubmit it with a new key.
If the runner is not open, the tools return an instruction to open the design in the PCB editor.
Refused, blocked or unavailable results are normal stop results.

## Status

Version 0.1.0 is the first public release. The package passed the Claude Code plugin validator
and the Codex package parser, and the server is live at `https://api.deltatronix.io/mcp`. Sign-in,
authenticated edits and saved receipts from each client have not been checked end to end yet.
Please report problems in this repository's issues.

## Changelog

- **0.1.0 (2026-11-11):** first public release. Shared skill, Claude Code and Codex manifests,
  and the `pcb` MCP server.

## License

MIT for the files in this repository. See [LICENSE](LICENSE). The Deltatronix service is
governed by its own terms.
