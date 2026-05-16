
## Installation in GT

```st
Metacello new
	repository: 'github://mariari/ElixirGtBridge:master/src';
	baseline: 'Gt4beam';
	load
```

## Load Lepiter

After installing with Metacello, you will be able to execute

```
#BaselineOfGt4beam asClass loadLepiter
```

## Installing in an Elixir Project

The package is [available on Hex](https://hex.pm/packages/gt_bridge).
Add `gt_bridge` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:gt_bridge, "~> 0.17.1"}
  ]
end
```
