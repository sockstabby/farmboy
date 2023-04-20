defmodule HordeTaskRouter.Router do
  @moduledoc """
  Fake module that emulates deleting records randomly.
  """

  use GenServer
  require Logger

  alias __MODULE__.Runner

  @default_timeout :timer.seconds(2)

  def start_link(opts) do
    #name = Keyword.get(opts, :name, __MODULE__)
    name = "taskrouter"
    tname = via_tuple(name)
    IO.inspect( tname )
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.start_link(__MODULE__, timeout, name: via_tuple(name))
  end


  def monitor_global_task(nil) do
    Logger.debug("monitor_global_task nil")
  end

  def monitor_global_task( [ task | _tail] ) do
    Logger.debug("monitor_global_task []")
    %{pid: pid } = task
     Logger.debug("pid = ")
     IO.inspect(pid)
     Process.link(pid)
  end

  @impl true
  @spec init(non_neg_integer) :: {:ok, non_neg_integer}
  def init(timeout) do
    Process.flag(:trap_exit, true)
    value = get_global_tasks()
    monitor_global_task(value)
    Logger.debug("global tasks = ")
    IO.inspect(value)
    {:ok, timeout}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    IO.puts("DOWN CALLED ref = ")
    IO.inspect(ref)
    #{:noreply, state}
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    IO.puts("Unexpected message in handle_info: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:run_task, %{object: _o, method: _m, args: _a} }, state) do
    Logger.debug("handle_cast")
    #Logger.debug("o=#{o}")
    #Logger.debug("m=#{m}")
    #IO.puts("a =")
    #IO.inspect(a)

    task = Task.Supervisor.async_nolink({Chat.TaskSupervisor, :foo@localhost}, FirstDistributedTask, :hello, [12])
    IO.inspect(task)
    Horde.Registry.put_meta(HordeTaskRouter.HordeRegistry, "tasks", [task])

    {:noreply, state}
  end



  def via_tuple(name), do: {:via, Horde.Registry, {HordeTaskRouter.HordeRegistry, name}}

  defp get_global_tasks() do

    case Horde.Registry.meta(HordeTaskRouter.HordeRegistry, "tasks") do
      {:ok, tasks} ->
        tasks
      :error ->
        nil
    end
  end

end
