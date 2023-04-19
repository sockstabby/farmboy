# HordeBackgroundJob

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `horde_background_job` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:horde_background_job, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/horde_background_job](https://hexdocs.pm/horde_background_job).




my model is a little different

they supervise DatabaseCleaner - a genserver with an execute method that
calls a task. ( in same node )

my case 
instead of calling a task in same node lets call a task in 
another node. lots of reuse here. 