defmodule HordeTaskRouter.Router do
  @moduledoc """
  Fake module that emulates deleting records randomly.
  """

  use GenServer
  require Logger

  alias __MODULE__.Runner

  @default_timeout :timer.seconds(2)

  def start_link(opts) do
    name = "taskrouter"
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case GenServer.start_link(__MODULE__, timeout, name: via_tuple(name)) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("already started at #{inspect(pid)}, returning :ignore")
        :ignore
      end
  end


  def monitor_global_tasks([]) do
    Logger.debug("all done. monitor_global_task empty")
  end

  def monitor_global_tasks([task | tail]) do
    Logger.debug("we have some tasks to monitor")
    %{pid: pid } = task
     Logger.debug("monitorig pid = ")
     IO.inspect(pid)
     Process.link(pid)
     monitor_global_tasks(tail)
  end

  @impl true
  def init(_timeout) do
    Logger.debug("init called ")

    IO.inspect(self())

    Process.flag(:trap_exit, true)
    tasks = get_global_tasks()

    IO.inspect(tasks)

    Horde.Registry.put_meta(HordeTaskRouter.HordeRegistry, "tasks", [])

    #important that we do this
    monitor_global_tasks(tasks)

    Logger.debug("global tasks = ")
    IO.inspect(tasks)

    {:ok, %{count: 0, tasks: tasks}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    Logger.debug("DOWN CALLED ref = ")
    IO.inspect(ref)
    tasks = Map.get(state, :tasks)

    filtered = Enum.filter(tasks, fn x -> x.ref != ref end)

    Logger.debug("tasks after filter =")
    IO.inspect(filtered)

    {:noreply, Map.put(state, :tasks, filtered )}
  end

  @impl true
  def handle_info({:exit, reason}, _state) do
    IO.inspect(":exit received")
    exit(reason)
  end

  @impl true
  def handle_info(msg, state) do
    IO.puts("Unexpected message in handle_info: #{inspect(msg)}")
    {:noreply, state}
  end

  # the following function can be called from the UI
  # or from the scheduler.
  @impl true
  def handle_cast({:run_task, %{object: _object, method: method, args: args, roomid: roomid, origin_node: origin_node} }, state) do

    available_workers =
        Node.list
        |> Enum.map(fn x -> Atom.to_string(x) end )
        |> Enum.filter(fn x -> String.contains?(x, "worker") end )

    IO.inspect(available_workers)

    total_workers = length(available_workers)
    worker_index = rem(state.count, total_workers)

    IO.inspect("worker count = #{total_workers}")
    IO.inspect("worker_index = #{worker_index}")
    IO.inspect("count = #{state.count}")

    worker_node = Enum.at(available_workers, worker_index)
    IO.inspect("worker node = #{worker_node}")

    task = Task.Supervisor.async_nolink({Chat.TaskSupervisor,  String.to_atom(worker_node)}, FirstDistributedTask, String.to_atom(method), [roomid, origin_node, args])
    IO.inspect(task)

    new_state = Map.put(state, :count, state.count + 1 )
    new_tasks = [task | state.tasks]
    new_state2 = Map.put(new_state, :tasks, new_tasks)
    {:noreply, new_state2 }
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("#{__MODULE__}.terminate/2 called with reason: #{inspect reason}")
    #save off our task state state
    Horde.Registry.put_meta(HordeTaskRouter.HordeRegistry, "tasks", state.tasks)
    Logger.info("saving state to horde memory")
  end

  def via_tuple(name), do: {:via, Horde.Registry, {HordeTaskRouter.HordeRegistry, name}}

  defp get_global_tasks() do

    case Horde.Registry.meta(HordeTaskRouter.HordeRegistry, "tasks") do
      {:ok, tasks} ->
        tasks
      :error ->
        []
    end
  end

end
