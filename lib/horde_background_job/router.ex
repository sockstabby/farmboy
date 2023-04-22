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
    {:ok, timeout}
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
  def handle_cast({:run_task, %{object: object, method: method, args: args, roomid: roomid} }, state) do
    Logger.debug("handle_cast")
    #Logger.debug("o=#{o}")
    #Logger.debug("m=#{m}")
    #IO.puts("a =")
    #IO.inspect(a)

    task = Task.Supervisor.async_nolink({Chat.TaskSupervisor, :"foo@127.0.0.1"}, FirstDistributedTask, String.to_atom(method), args)
    IO.inspect(task)
    append_task_to_global_tasks(task)
    #Horde.Registry.put_meta(HordeTaskRouter.HordeRegistry, "tasks", [task])
    {:noreply, state}
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
