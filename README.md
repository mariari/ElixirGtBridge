
## Installation in GT

```st
Metacello new
	repository: 'github://mariari/gt4beam:master/src';
	baseline: 'Gt4beam';
	load
```

## Load Lepiter

After installing with Metacello, you will be able to execute

```
#BaselineOfGt4beam asClass loadLepiter
```

## Installing in an Elixir Project

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `gt_bridge` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:gt_bridge, "~> 0.1.0"}
  ]
end
```
