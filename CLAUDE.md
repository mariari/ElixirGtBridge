# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Conventions

Follow these skills for all work in this repository:

- @.claude/skills/general-conventions/SKILL.md
- @.claude/skills/elixir-conventions/SKILL.md
- @.claude/skills/git-conventions/SKILL.md

## Build & Development Commands

```bash
mix test              # Run all tests
mix test test/gt_bridge_test.exs:5   # Run a single test by line number
mix format            # Format code (98-char line length)
mix dialyzer          # Static type analysis
```

## What This Project Is

GtBridge is a bridge between GT (Glamorous Toolkit, a Smalltalk IDE) and the BEAM VM. It lets GT remotely evaluate Elixir code, inspect BEAM objects, and render Phlow views of Elixir data structures inside GT's inspector.

## Architecture

**Supervision tree** (started by `GtBridge.start/2`):

```
GtBridge.Supervisor
  ├── EvaluationSupervisor    — DynamicSupervisor for GtBridge.Eval instances
  ├── Tcp.Supervisor          — DynamicSupervisor for Tcp.Listener / Tcp.Connection
  ├── GtBridge.Http.Supervisor — DynamicSupervisor for Plug.Cowboy HTTP servers
  ├── GtBridge.Views          — GenServer registry of Phlow view functions
  └── GtBridge.ObjectRegistry — GenServer mapping object IDs to values
```

**Data flow:** GT sends HTTP POSTs (`/ENQUEUE`, `/GET_VIEWS`, `/EVAL`) or connects via TCP (MessagePack). `GtBridge.Eval` evaluates code with `Code.eval_string/2`, maintains per-session bindings, registers complex results in `ObjectRegistry`, and serializes responses via `GtBridge.Serializer`. Objects are sent as `{exid, exclass}` references; GT lazily requests views/attributes on demand.

**Key subsystems:**

- **Eval** (`lib/gt_bridge/eval.ex`) — GenServer holding bindings per evaluation session. Created dynamically under `EvaluationSupervisor`.
- **Phlow views** (`lib/gt_bridge/phlow/`) — View specs (List, ColumnedList, ColumnedTree, Text, Empty) declared via `defview/2` macro in `GtBridge.View`. Views are registered per-module in the `GtBridge.Views` GenServer.
- **Serializer** (`lib/gt_bridge/serializer.ex`) — Custom JSON encoding: PIDs as `["__pid__", ...]`, binaries as `["__base64__", ...]`, atoms preserved via Jexon.
- **HTTP** (`lib/gt_bridge/http/router.ex`) — Plug.Router handling GT's HTTP protocol.
- **TCP** (`lib/tcp/`) — Listener/Connection pair using MessagePack via `msgpax`.

**Smalltalk side** (`src/Gt4beam/`) — GT classes for view declarations, link commands, deserialization, and snippet editing. Installed via Metacello from `github://mariari/ElixirGtBridge`.

## Testing Pattern

Tests delegate to example modules in `lib/examples/e_*.ex`. Each example function uses ExUnit assertions and demonstrates a feature. Tests are in `test/gt_bridge_test.exs` and call these example functions directly.
