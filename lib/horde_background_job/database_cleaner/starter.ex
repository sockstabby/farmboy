defmodule HordeTaskRouter.Router.Starter do
  @moduledoc """
  Module in charge of starting and monitoring  the `Router`
  process, restarting it when necessary.
  """

  require Logger

  alias HordeTaskRouter.{Router, HordeRegistry, HordeSupervisor}

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :temporary,
      shutdown: 500
    }
  end

  def start_link(opts) do
    name =
      opts
      |> Keyword.get(:name, Router)
      |> via_tuple()

    opts = Keyword.put(opts, :name, name)

    child_spec = %{
      id: Router,
      start: {Router, :start_link, [opts]}
    }

    HordeSupervisor.start_child(child_spec)

    :ignore
  end

  def whereis(name \\ Router) do
    name
    |> via_tuple()
    |> GenServer.whereis()
  end

  defp via_tuple(name) do
    {:via, Horde.Registry, {HordeRegistry, name}}
  end
end
