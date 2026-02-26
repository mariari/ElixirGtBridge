---
name: elixir-conventions
description: Elixir-specific coding patterns and conventions.
---

# Elixir Conventions

## Control Flow

- Prefer `with` chains over nested `case`.
- Use `Enum.reduce_while` or `Enum.flat_map` over `Enum.reduce`
  with internal conditionals.
- Pattern match in function heads rather than branching in the body.

## Types & Structs

- Use `typedstruct` for struct definitions.
- Prefer union types for option lists over keyword defaults:
  ```elixir
  @type startup_options ::
          {:name, atom()}
          | {:timeout, pos_integer()}

  @spec start_link(list(startup_options())) :: GenServer.on_start()
  ```
- Keep type definitions near the top, after `use`/`alias` blocks.

## GenServer

- `handle_call` body: `{:reply, do_foo(...), state}` — core logic
  in the `do_` function.
- Never call a callback from another callback.
- Organize GenServer modules into clear sections:
  ```elixir
  ############################################################
  #                        Public API                        #
  ############################################################

  ############################################################
  #                    GenServer Callbacks                   #
  ############################################################

  ############################################################
  #                   Private Implementation                 #
  ############################################################
  ```

## State Boundaries

Choose where state lives based on two questions:

1. **Should users or external code be able to query it?**
   If yes → persistent storage (DB on disk).
2. **Can we tolerate losing it on crash or shutdown?**
   If yes → process state is fine for pure implementation details.
   If we can tolerate loss on shutdown but not on crash →
   an ETS/Mnesia table (survives process crashes, lost on VM stop)
   may be the right middle ground.

## Documentation

- First-person voice: "I am the X module." / "I return the Y."
- `@moduledoc` starts with one-sentence purpose.
- `### Public API` section listing all public functions.
- All public functions need `@doc` and `@spec`.

## Examples

- Live in `lib/examples/e_<module>.ex`.
- Module name pattern: `E<Module>` (e.g., `ENode`, `EShard`).
- Use `import ExUnit.Assertions` for `assert`.

## Interactive Testing

- Run one-off expressions: `timeout 60 mix run -e 'code'`
  (never use `--no-halt`, it hangs the VM).
- Inspect process state: `:sys.get_state(pid)`

## Formatting

- 98 character line length.
- Run `mix format` before finalizing.
- Section headers use banner comments:
  ```elixir
  ############################################################
  #                      Section Name                        #
  ############################################################
  ```
