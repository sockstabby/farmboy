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

    Logger.debug("name =")
    IO.inspect( name )


    Logger.debug("getting tuple name")
    tname = via_tuple(name)

    IO.inspect( tname )

    Logger.debug("done getting tuple name")


    timeout = Keyword.get(opts, :timeout, @default_timeout)

    #GenServer.start_link(__MODULE__, timeout, name: name)

    GenServer.start_link(__MODULE__, timeout, name: via_tuple(name))

  end

  @impl GenServer
  @spec init(non_neg_integer) :: {:ok, non_neg_integer}
  def init(timeout) do
    Process.flag(:trap_exit, true)

    schedule(timeout)
    {:ok, timeout}
  end

  @impl GenServer
  def handle_info(:execute, timeout) do

    Logger.debug("calling the task hello")

    task = Task.Supervisor.async({Chat.TaskSupervisor, :foo@localhost}, FirstDistributedTask, :hello, [12])
    Logger.debug("called the task hello")

    IO.inspect(task)

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

end
