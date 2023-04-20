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

    #GenServer.start_link(__MODULE__, timeout, name: name)

    GenServer.start_link(__MODULE__, timeout, name: via_tuple(name))

  end

  @impl GenServer
  @spec init(non_neg_integer) :: {:ok, non_neg_integer}
  def init(timeout) do
    Logger.debug("initializing")

    Process.flag(:trap_exit, true)

    Logger.debug("before")

    value = get_global_tasks()

    Logger.debug("value = ")

    IO.inspect(value)

    Logger.debug("after")


    Logger.debug("global tasks = ")
    #IO.inspect(tasks)

    schedule(timeout)
    {:ok, timeout}
  end



  @impl GenServer
  def handle_info(:execute, timeout) do


    Process.sleep(5000)


    value = get_global_tasks()

    Logger.debug("handle_info value = ")

    IO.inspect(value)


    Process.sleep(5000)



    task = Task.Supervisor.async({Chat.TaskSupervisor, :foo@localhost}, FirstDistributedTask, :hello, [12])
    #IO.inspect(task)

    Horde.Registry.put_meta( HordeTaskRouter.TaskRegistry, "tasks", [task])

    Logger.debug("after put reading")

    Process.sleep(5000)

    {:ok, tasks } = Horde.Registry.meta(HordeTaskRouter.TaskRegistry, "tasks")

    IO.inspect(tasks)

    Logger.debug("after reading")

    {:noreply, timeout}
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
  def handle_cast({:run_task, %{object: o, method: m, args: a} }, state) do
    Logger.debug("handle_cast")

    Logger.debug("o=#{o}")
    Logger.debug("m=#{m}")

    IO.puts("a =")
    IO.inspect(a)

    {:noreply, state}
  end

  defp schedule(timeout) do
    log("scheduling for #{timeout}ms")
    Process.send_after(self(), :execute, timeout)
  end

  defp log(text) do
    Logger.info("----[#{node()}-#{inspect(self())}] #{__MODULE__} #{text}")
  end

  def via_tuple(name), do: {:via, Horde.Registry, {HordeTaskRouter.HordeRegistry, name}}

  defp get_global_tasks() do

    case Horde.Registry.meta(HordeTaskRouter.TaskRegistry, "tasks") do
      {:ok, tasks} ->
        tasks
      :error ->
        nil
    end
  end

end
