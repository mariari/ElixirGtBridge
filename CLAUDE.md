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

## GT / Smalltalk Side (`src/Gt4beam/`)

Installed via Metacello from `github://mariari/ElixirGtBridge:master/src`. Classes are in Tonel format.

**Proxy objects** — `BeamProxyObject` wraps remote Elixir objects by `exid`/`exclass`. Attributes are lazy-loaded via `GtBridge.ObjectRegistry.get_attribute(exid, :attr)`. A weak registry with finalizers calls `GtBridge.Eval.remove(exid)` for GC cleanup. Subclasses:
- `BeamPIDObject` — processes (supervision tree via `ViewHelpers`, state via `:sys.get_state`)
- `BeamListObject` — lists (indexed access)
- `BeamTupleObject` — tuples (converts via `Tuple.to_list()`)
- `BeamAtomObject` — atoms (standalone, not a proxy; resolves registered names)
- `BeamBridgeEvalError` — wraps `GtBridge.Eval.Error`

**Communication layer:**
- `BeamLinkApplication` — singleton managing the bridge connection
- `BeamLinkBeamProcess` — starts `iex -S mix` and HTTP listeners
- `BeamLinkHttpMessageBroker` — HTTP transport to the Elixir side
- `BeamLinkCommandFactory` — wraps code in `GtBridge.Eval.notify()` for async callbacks
- `ElixirLinkCommand` — represents a code evaluation command
- `BeamLinkDeserializer` / `ElixirLinkNeoJsonSerializer` — handles `["__atom__", ...]` and `["__base64__", ...]` markers, builds proxies from `{exid, exclass}` responses

**Remote view rendering** — `GtBeamViewDeclaration` deserializes Phlow view specs from the BEAM. `fromRawData:` dispatches to subclasses by `remoteName`:
- `GtBeamListViewDeclaration` → `GtPhlowListViewSpecification`
- `GtBeamColumnedListViewDeclaration` → `GtPhlowColumnedListViewSpecification`
- `GtBeamColumnedTreeViewDeclaration` → `GtPhlowColumnedTreeViewSpecification`
- `GtBeamTextEditorViewDeclaration` → `GtPhlowTextEditorViewSpecification`

**Code evaluation (Lepiter integration):**
- `LeElixirSnippet` → `LeElixirSnippetElement` → `LeElixirApplicationStrategy` (server lifecycle)
- `GtElixirCoderModel` — editor model with evaluate/inspect actions, `ElixirParser` for syntax
- `BeamStylerUtilities` + `GtSmaCCParserStyler` extension — syntax highlighting with rainbow brackets

**Elixir functions called from GT:**
- `GtBridge.GtViewedObject.get_views_declarations_by_id(exid)` — get view specs
- `GtBridge.ObjectRegistry.{resolve, get_attribute, list_attributes}` — object access
- `GtBridge.Eval.{notify/3, remove/1}` — async eval and GC cleanup
- `GtBridge.ViewHelpers.{determine_supervisor/1, build_supervision/1}` — PID views

## Testing Pattern

Tests delegate to example modules in `lib/examples/e_*.ex`. Each example function uses ExUnit assertions and demonstrates a feature. Tests are in `test/gt_bridge_test.exs` and call these example functions directly.
