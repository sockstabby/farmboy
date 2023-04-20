# HordeTaskRouter

Monitors all launched tasks

To support updates Whenever it starts it monitors whatever is in the 
horde registry

Registry simply stores pids

and task router calls monitor on them 

If pid of task process disappears while router is not monitoring 
it wont matter because when it restarts it will rectify. 

HEres the proof
oldpid = spawn(fn -> 1 + 2 end)
#PID<0.111.0>
iex(10)> pid = spawn(fn -> 1 + 2 end)
#PID<0.119.0>
iex(11)> Process.monitor(pid)
#Reference<0.109932022.3302227970.196886>
iex(15)> flush()
{:DOWN, #Reference<0.109932022.3302227970.196886>, :process, #PID<0.119.0>,
 :noproc}
:ok
iex(16)> flush()
:ok
iex(17)> Process.monitor(oldpid)
#Reference<0.109932022.3302227970.196940>
iex(18)> flush()                
{:DOWN, #Reference<0.109932022.3302227970.196940>, :process, #PID<0.111.0>,
 :noproc}
:ok











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

they supervise Router - a genserver with an execute method that
calls a task. ( in same node )

my case 
instead of calling a task in same node lets call a task in 
another node. lots of reuse here. 


