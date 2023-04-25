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
  @spec init(non_neg_integer) :: {:ok, non_neg_integer}
  def init(timeout) do
    Logger.debug("init called")

    Process.flag(:trap_exit, true)
    value = get_global_tasks()
    monitor_global_tasks(value)
    Logger.debug("global tasks = ")
    IO.inspect(value)

    {:ok, %{count: 0}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    Logger.debug("DOWN CALLED ref = ")
    IO.inspect(ref)
    Process.sleep(500)

    Logger.debug("tasks before filter =")
    tasks = get_global_tasks()
    IO.inspect(tasks)
    Process.sleep(500)

    filtered = Enum.filter(tasks, fn x -> x.ref != ref end)

    Logger.debug("tasks after filter =")
    IO.inspect(filtered)
    #Process.sleep(500)

    # not atomic. however if we can guarantee that this is the only process running,
    # we dont need to worry about it
    Horde.Registry.put_meta(HordeTaskRouter.HordeRegistry, "tasks", filtered)
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    IO.puts("Unexpected message in handle_info: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:run_task, %{object: _object, method: method, args: args, roomid: roomid} }, state) do

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



    task = Task.Supervisor.async_nolink({Chat.TaskSupervisor,  String.to_atom(worker_node)}, FirstDistributedTask, String.to_atom(method), [roomid, args])
    IO.inspect(task)
    append_task_to_global_tasks(task)

    {:noreply, %{count: state.count + 1} }
  end

  @impl true
  def handle_cast({:get_tasks }, state) do
    Logger.debug("get_tasks")
    tasks = get_global_tasks()
    IO.inspect(tasks)
    {:noreply, state }
  end

  def append_task_to_global_tasks(task) do
    tasks = get_global_tasks()
    new_tasks = [task | tasks]
    Horde.Registry.put_meta(HordeTaskRouter.HordeRegistry, "tasks", new_tasks)
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
