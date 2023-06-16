defmodule Farmboy.Router do
  @moduledoc """
  This module discovers workers and initalizes task schedules with Quantum. When it is time to run, it
  invokes the task on worker node passing in the task configuration.
  """

  use GenServer
  import Crontab.CronExpression

  # frequency to poll workers for their load average
  @worker_poll_freq 5_000
  # channel logs on the client websocket
  @channel_id "123"

  require Logger

  def start_link(_opts) do
    case GenServer.start_link(__MODULE__, nil, name: via_tuple("taskrouter")) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("already started at #{inspect(pid)}, returning :ignore")
        :ignore
    end
  end

  @doc """
  This method is called from Quantum when a item is scheduled to run.
  """
  def execute_task(nil) do
    Logger.debug("Task does not exist")
  end

  def execute_task(task) when task.enabled == false,
    do: Logger.debug("Task is disabled")

  def execute_task(task) when task.enabled == true,
    do:
      GenServer.cast(
        {:via, Horde.Registry, {Farmboy.HordeRegistry, "taskrouter"}},
        {:run_task,
         %{
           id: "#{task.taskid}",
           args: task.config,
           roomid: @channel_id,
           origin_node: "scheduler",
           instance: task.id
         }}
      )

  @doc """
  This method is called from Quantum when a item is scheduled to run. We'll read the
  task configuration from the db and pass it to the task.
  """
  def invoke_task(taskid) do
    task = Scheduler.ScheduledTasks |> Tasks.Repo.get(taskid)
    execute_task(task)
  end

  @impl true
  def init(_opts) do
    # we monitor nodes so workers can be added at any time
    :net_kernel.monitor_nodes(true, node_type: :visible)

    # get the currently running workers
    available_workers =
      Node.list()
      |> Enum.map(fn x -> Atom.to_string(x) end)
      |> Enum.filter(fn x -> String.contains?(x, "worker") end)

    # query all nodes for their task metadata.
    # we can ignore the retun value because this is async
    # so results are returned in handle_info.
    _deets =
      Enum.map(available_workers, fn worker_node ->
        %{
          worker: worker_node,
          task:
            Task.Supervisor.async_nolink(
              {Chat.TaskSupervisor, String.to_atom(worker_node)},
              DistributedTask,
              String.to_atom("get_worker_details"),
              []
            )
        }
      end)

    # load all scheduled tasks from a db table
    scheduled_tasks = Scheduler.ScheduledTasks |> Tasks.Repo.all()
    Logger.debug("tasks from db = #{inspect(scheduled_tasks)}")

    # initialze Quantum with the tasks we read
    _ret =
      Enum.map(scheduled_tasks, fn i ->
        Scheduler.Quantum.new_job()
        |> Quantum.Job.set_name(i.id |> Integer.to_string() |> String.to_atom())
        |> Quantum.Job.set_schedule(sigil_e(i.schedule, nil))
        |> Quantum.Job.set_task({Farmboy.Router, :invoke_task, [i.id]})
        |> Scheduler.Quantum.add_job()
      end)

    # initiate polling on workers to get their load average
    Process.send_after(self(), :poll_worker_resources, @worker_poll_freq)

    # finally return the initial state
    {:ok, %{count: 0, tasks: [], worker_details: %{}, resource_info: %{}, task_workers: %{}}}
  end

  @impl true
  def handle_info({:probe_worker, node}, state) do
    Task.Supervisor.async_nolink(
      {Chat.TaskSupervisor, node},
      DistributedTask,
      :get_worker_details,
      []
    )

    {:noreply, state}
  end

  @impl true
  def handle_info(:poll_worker_resources, state) do
    available_workers =
      Node.list()
      |> Enum.map(fn x -> Atom.to_string(x) end)
      |> Enum.filter(fn x -> String.contains?(x, "worker") end)

    # we can ignore return value from async_nolink because
    # results are returned in handle_info
    _ret =
      Enum.map(available_workers, fn worker_node ->
        %{
          worker: worker_node,
          task:
            Task.Supervisor.async_nolink(
              {Chat.TaskSupervisor, String.to_atom(worker_node)},
              DistributedTask,
              String.to_atom("get_worker_resources"),
              []
            )
        }
      end)

    Process.send_after(self(), :poll_worker_resources, @worker_poll_freq)
    {:noreply, state}
  end

  # This is called when a task we launched terminates. We just
  # clear it from our tasks list.
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    tasks = Map.get(state, :tasks)
    filtered = Enum.filter(tasks, fn x -> x.ref != ref end)
    {:noreply, Map.put(state, :tasks, filtered)}
  end

  # This is called when a node in the cluster starts up. We'll send a probe_message
  # to ourself after a second to load task metadata.
  def handle_info({:nodeup, node, _node_type}, state) do
    if String.contains?(Atom.to_string(node), "worker") do
      Logger.debug("WORKER ADDED ")
      Process.send_after(self(), {:probe_worker, node}, 1000)
    end

    {:noreply, state}
  end

  # This is called whenever a node in the cluster goes down.
  # When this happens we need to update our available workers so
  # we dont attempt to schedule tasks on a node that doesn't exist.
  # We also clear everything that we learned about the node.
  def handle_info({:nodedown, node, _node_type}, state) do
    new_task_workers =
      Enum.reduce(state.task_workers, %{}, fn {k, v}, acc ->
        filtered_workers = Enum.filter(v, fn x -> x != node end)
        Map.put(acc, k, filtered_workers)
      end)

    new_resource_info =
      Enum.reduce(state.resource_info, %{}, fn {k, v}, acc ->
        if String.to_atom(k) == node do
          acc
        else
          Map.put(acc, k, v)
        end
      end)

    new_worker_details =
      Enum.reduce(state.worker_details, %{}, fn {k, v}, acc ->
        if k == node do
          acc
        else
          Map.put(acc, k, v)
        end
      end)

    Logger.debug("new_resource_info = #{inspect(new_resource_info)}")

    new_state = Map.put(state, :task_workers, new_task_workers)
    new_state = Map.put(new_state, :worker_details, new_worker_details)
    {:noreply, Map.put(new_state, :resource_info, new_resource_info)}
  end

  # This is the return from an async_nolink call we made to get the cpu load average
  # from a worker.
  @impl true
  def handle_info({_ref, %{worker_resource_info: deets}}, state) do
    old_val = state.resource_info
    # here we convert atom to string for display purposes only
    new_val = Map.put(old_val, Atom.to_string(deets.host), deets.avg5)
    ret = Map.put(state, :resource_info, new_val)

    {:noreply, ret}
  end

  # This is the return from an async_nolink call we made to get task metadata
  # from a worker.
  @impl true
  def handle_info({_ref, %{worker_registration: deets}}, state) do
    %{host: host, items: work_items} = deets

    # add task to task_workers and append host
    Logger.debug("host: #{inspect(host)}")
    Logger.debug("items: #{inspect(work_items)}")

    task_workers = state.task_workers

    # iterate work_items add each to global array keyed on task
    task_worker_map =
      Enum.reduce(work_items, state.task_workers, fn i, acc ->
        task_hosts = Map.get(task_workers, "#{i.taskid}", [])
        new_task_hosts = [host | task_hosts]
        new_task_workers = Map.put(acc, "#{i.taskid}", new_task_hosts)
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

  # This is called from the app server to remove an instance of a task.
  # When called we remove it from Quantum.
  @impl true
  def handle_cast({:task_item_removed, task}, state) do
    id = task.id |> Integer.to_string() |> String.to_atom()
    Logger.debug("task_item_removed called, id = #{inspect(id)} ")
    Scheduler.Quantum.delete_job(id)
    Logger.debug("Task item removed")
    {:noreply, state}
  end

  # This is called from the app server to add a new instance of a task.
  # When called we add it to Quantum.
  @impl true
  def handle_cast({:task_item_added, {:ok, task}}, state) do
    id = task.id |> Integer.to_string() |> String.to_atom()

    Logger.debug("task_item_added called, id = #{inspect(id)} ")

    Scheduler.Quantum.new_job()
    |> Quantum.Job.set_name(id)
    |> Quantum.Job.set_schedule(sigil_e(task.schedule, nil))
    |> Quantum.Job.set_task({Farmboy.Router, :invoke_task, [task.id]})
    |> Scheduler.Quantum.add_job()

    Logger.debug("added new task")
    {:noreply, state}
  end

  # This is called from the app server when the schedule or the timing of a task changes.
  # When this happens we need to delete the item from the schedule and then re-add it.
  @impl true
  def handle_cast({:task_schedule_changed, task}, state) do
    id = task.id |> Integer.to_string() |> String.to_atom()

    Scheduler.Quantum.delete_job(id)

    Scheduler.Quantum.new_job()
    |> Quantum.Job.set_name(id)
    |> Quantum.Job.set_schedule(sigil_e(task.schedule, nil))
    |> Quantum.Job.set_task({Farmboy.Router, :invoke_task, [task.id]})
    |> Scheduler.Quantum.add_job()

    Logger.debug("re-added task with new schedule")

    {:noreply, state}
  end

  # This is called to run a task.
  @impl true
  def handle_cast(
        {:run_task,
         %{instance: instance, id: taskid, args: args, roomid: roomid, origin_node: origin_node}},
        state
      ) do
    Logger.debug("RUNNING TASK taskid = #{inspect(taskid)}")

    # see if this instance exists already.
    # if so we wont run another instance.

    index = Enum.find_index(state.tasks, fn x -> x.instance == instance end)

    case index do
      # nil = task instance is running so all good to run a new instance
      nil ->
        # get the workers that support this taskid aka task
        workers = Map.get(state.task_workers, taskid, [])

        workers_with_resources =
          Enum.map(workers, fn i ->
            resource_info = Map.get(state, :resource_info, %{})
            load = Map.get(resource_info, Atom.to_string(i), 0)
            %{worker: i, load: load}
          end)

        # now get the worker with the least load
        worker_choice =
          Enum.reduce(workers_with_resources, {"fake_worker", 100_000_000}, fn i, acc ->
            if i.load < elem(acc, 1), do: {i.worker, i.load}, else: acc
          end)

        Logger.debug("chosen worker = #{inspect(worker_choice)}")

        worker_node = elem(worker_choice, 0)

        iso = DateTime.utc_now() |> DateTime.to_iso8601()

        task =
          Task.Supervisor.async_nolink(
            {Chat.TaskSupervisor, worker_node},
            DistributedTask,
            :run,
            [roomid, origin_node, instance, taskid, args]
          )

        task = Map.from_struct(task)
        task = Map.put(task, :worker, worker_node)
        task = Map.put(task, :instance, instance)
        task = Map.put(task, :taskid, taskid)
        task = Map.put(task, :args, args)
        task = Map.put(task, :time_started, iso)

        Logger.info(task)

        new_state = Map.put(state, :count, state.count + 1)
        new_tasks = [task | state.tasks]
        new_state2 = Map.put(new_state, :tasks, new_tasks)
        {:noreply, new_state2}

      _ ->
        Logger.debug("Task is still running.")
        {:noreply, state}
    end
  end

  def via_tuple(name), do: {:via, Horde.Registry, {Farmboy.HordeRegistry, name}}
end
