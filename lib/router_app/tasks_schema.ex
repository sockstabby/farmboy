defmodule Scheduler.ScheduledTasks do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tasks" do
    field :config, :string
    field :enabled, :boolean, default: false
    field :name, :string
    field :schedule, :string
    field :slack, :boolean, default: false
    field :taskid, :integer

    timestamps()
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [:taskid, :name, :schedule, :enabled, :config, :slack])
    |> validate_required([:taskid, :name, :schedule, :enabled, :config, :slack])
  end
end
