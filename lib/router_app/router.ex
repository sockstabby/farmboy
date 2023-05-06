defmodule HordeTaskRouter.Router do
  @moduledoc """
  Fake module that emulates deleting records randomly.
  """

  use GenServer
  import Crontab.CronExpression

  @worker_poll_freq  5_000
  require Logger

  def start_link(opts) do
    name = "taskrouter"

    case GenServer.start_link(__MODULE__, nil, name: via_tuple(name)) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("already started at #{inspect(pid)}, returning :ignore")
        :ignore
      end
  end

  def execute_task(task) do
    Logger.debug("Executing task")

    parms = %{object: "Task #{task.taskid}",
      method: "#{task.taskid}",
      args: task.config,
      roomid: "room:123",
      origin_node: "scheduler"
    }

    if task.enabled == true do
      GenServer.cast({:via, Horde.Registry, {HordeTaskRouter.HordeRegistry, "taskrouter"}},
       {:run_task, parms})
    end
  end

  def execute_task(nil) do
    Logger.debug("Task does not exist")
  end

  def hello(taskid) do
    task = Scheduler.ScheduledTasks |> Tasks.Repo.get(taskid)
    execute_task(task)
  end

  def monitor_global_tasks([]) do
    Logger.debug("monitor_global_task empty")
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
  def init(_opts) do
    :net_kernel.monitor_nodes(true, node_type: :visible)
    Logger.debug("self = #{inspect(self())}")
    Process.flag(:trap_exit, true)
    tasks = get_global_tasks()
    Horde.Registry.put_meta(HordeTaskRouter.HordeRegistry, "tasks", [])

    #important that we do this
    monitor_global_tasks(tasks)

    Logger.debug("global tasks = #{tasks}")

    available_workers =
      Node.list
      |> Enum.map(fn x -> Atom.to_string(x) end )
      |> Enum.filter(fn x -> String.contains?(x, "worker") end )


    # query workers
    _deets = Enum.map(available_workers, fn worker_node ->
        %{worker: worker_node, task: Task.Supervisor.async_nolink({Chat.TaskSupervisor,  String.to_atom(worker_node)}, FirstDistributedTask, String.to_atom("get_worker_details"), []) }
    end)

    scheduled_tasks = Scheduler.ScheduledTasks |> Tasks.Repo.all
    Logger.debug("tasks from db = #{inspect(scheduled_tasks)}")

    ret_ = Enum.map(scheduled_tasks, fn i ->
      Scheduler.Quantum.new_job()
      |> Quantum.Job.set_name(i.id |> Integer.to_string() |> String.to_atom())
      |> Quantum.Job.set_schedule(sigil_e(i.schedule, nil) )
      |> Quantum.Job.set_task({HordeTaskRouter.Router, :hello, [i.id]})
      |> Scheduler.Quantum.add_job()
    end )


    #start polling workers load average
    Process.send_after(self(), :poll_worker_resources,  @worker_poll_freq)
    {:ok, %{count: 0, tasks: tasks, worker_details: %{}, resource_info: %{}, task_workers:  %{}}}
  end

  @impl true
  def handle_info({:probe_worker, node}, state) do
    Task.Supervisor.async_nolink({Chat.TaskSupervisor,  node}, FirstDistributedTask, String.to_atom("get_worker_details"), [])
  end

  @impl true
  def handle_info(:poll_worker_resources, state) do
    #Logger.debug("Poll worker resources")

    available_workers =
      Node.list
      |> Enum.map(fn x -> Atom.to_string(x) end )
      |> Enum.filter(fn x -> String.contains?(x, "worker") end )

    # when a schedule fires
    # we grab the list of workers
    # and then we join with resource_info to create a new array
    #[ { host: :worker1, avg5: 65}, ... ]

     # finally we sort the list and choose the item with the least
     # load average

    # query workers
    _deets = Enum.map(available_workers, fn worker_node ->
        %{worker: worker_node, task: Task.Supervisor.async_nolink({Chat.TaskSupervisor,  String.to_atom(worker_node)}, FirstDistributedTask, String.to_atom("get_worker_resources"), []) }
    end)

    Process.send_after(self(), :poll_worker_resources,  @worker_poll_freq)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    Logger.debug ("DOWN CALLED ref = #{inspect(ref)}")
    tasks = Map.get(state, :tasks)

    filtered = Enum.filter(tasks, fn x -> x.ref != ref end)

    {:noreply, Map.put(state, :tasks, filtered )}
  end

  @impl true
  def handle_info({:exit, reason}, state) do
    Logger.info(":exit received")
    exit(reason)
    {:noreply, state}
  end

  def handle_info({:nodeup, node, _node_type}, state) do
    n = Atom.to_string(node)

    if String.contains?(n, "worker") do
      Logger.debug("WORKER ADDED ")
      Process.send_after(self(), {:probe_worker, node },  1000)
    end

    {:noreply, state}
  end

  def handle_info({:nodedown, node, _node_type}, state) do

    new_task_workers = Enum.reduce(state.task_workers, %{}, fn({k, v}, acc) ->
        filtered_workers = Enum.filter(v, fn x -> x != node end )
        Map.put(acc, k, filtered_workers)
      end
    )

    new_resource_info = Enum.reduce(state.resource_info, %{}, fn({k, v}, acc) ->
        if String.to_atom(k) == node do
          acc
        else
          Map.put(acc, k, v)
        end
      end
    )

    new_worker_details = Enum.reduce(state.worker_details, %{}, fn({k, v}, acc) ->
      if k == node do
        acc
      else
        Map.put(acc, k, v)
      end
    end
  )

    Logger.debug("new_resource_info = #{inspect(new_resource_info)}")

    new_state = Map.put(state, :task_workers, new_task_workers)
    new_state = Map.put(new_state, :worker_details, new_worker_details)
    {:noreply,  Map.put(new_state, :resource_info, new_resource_info)}

  end

  @impl true
  def handle_info({_ref, %{worker_resource_info: deets}}, state) do
    old_val = state.resource_info

    #fix me deets.avg5 instead of :rand.uniform(700)
    new_val = Map.put( old_val, Atom.to_string(deets.host), :rand.uniform(700) )
    ret = Map.put( state, :resource_info, new_val)

    {:noreply, ret}
  end

  @impl true
  def handle_info({_ref, %{worker_registration: deets}}, state) do
    %{host: host, items: work_items} = deets

     #add task to task_workers and append host
     Logger.debug("host: #{inspect(host)}")
     Logger.debug("items: #{inspect(work_items)}")

    task_workers = state.task_workers

    #iterate work_items add each to global array keyed on task
    task_worker_map = Enum.reduce(work_items, state.task_workers, fn i, acc ->
      task_hosts = Map.get(task_workers, "#{i.taskid}", [] )
      new_task_hosts = [host | task_hosts]
      new_task_workers = Map.put(acc, "#{i.taskid}", new_task_hosts )
      new_task_workers
    end)

    new_worker_details = Map.put(state.worker_details, host, work_items)
    new_state = Map.put(state, :worker_details, new_worker_details)
    new_state = Map.put(new_state, :task_workers, task_worker_map)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    IO.puts("Unexpected message in handle_info: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:task_item_removed, task }, state) do
    id = task.id |> Integer.to_string() |> String.to_atom()

    Logger.debug("task_item_removed called, id = #{inspect(id)} ")

    Scheduler.Quantum.delete_job(id)
    Logger.debug("Task item removed")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:task_item_added, {:ok, task}}, state) do

    id = task.id |> Integer.to_string() |> String.to_atom()

    Logger.debug("task_item_added called, id = #{inspect(id)} ")

    Scheduler.Quantum.new_job()
      |> Quantum.Job.set_name(id)
      |> Quantum.Job.set_schedule(sigil_e(task.schedule, nil) )
      |> Quantum.Job.set_task({HordeTaskRouter.Router, :hello, [task.id]})
      |> Scheduler.Quantum.add_job()

    Logger.debug("added new task")
    {:noreply, state}
  end


  @impl true
  def handle_cast({:task_schedule_changed, task }, state) do
    # when this happens we need to delete the item from the schedule
    # and then re-add it.

    id = task.id |> Integer.to_string() |> String.to_atom()

    Scheduler.Quantum.delete_job(id)

    Scheduler.Quantum.new_job()
    |> Quantum.Job.set_name(id)
    |> Quantum.Job.set_schedule(sigil_e(task.schedule, nil) )
    |> Quantum.Job.set_task({HordeTaskRouter.Router, :hello, [task.id]})
    |> Scheduler.Quantum.add_job()

    Logger.debug("re-added task with new schedule")

    {:noreply, state}

  end


  # the following function can be called from the UI
  # or from the scheduler.
  @impl true
  def handle_cast({:run_task, %{object: _object, method: method, args: args, roomid: roomid, origin_node: origin_node} }, state) do
    Logger.debug("RUNNING TASK method = #{inspect(method)}")

    # get the workers for this method
    workers = Map.get(state.task_workers, method, [] )

    workers_with_resources = Enum.map(workers, fn i ->
      resource_info = Map.get(state, :resource_info, %{} )
      load = Map.get(resource_info, Atom.to_string(i), 0)
      %{worker: i, load: load  }
    end
    )

    # now get the worker with the least load
    worker_choice = Enum.reduce(workers_with_resources, {"fake_worker", 100_000_000 }, fn i, acc ->
        if i.load < elem(acc, 1), do: {i.worker, i.load }, else: acc
      end
    )

    Logger.debug("chosen worker = #{inspect(worker_choice)}")

    worker_node = elem(worker_choice, 0)

    task = Task.Supervisor.async_nolink({Chat.TaskSupervisor,  worker_node}, FirstDistributedTask, :hello, [roomid, origin_node, method, args])
    task =  Map.from_struct(task)
    task = Map.put(task, :worker, worker_node )
    task = Map.put(task, :method, method )
    task = Map.put(task, :args, args )
    Logger.info(task)

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
    {:noreply, state }
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
