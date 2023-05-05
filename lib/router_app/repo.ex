defmodule Tasks.Repo do
  use Ecto.Repo,
    otp_app: :task_router,
    adapter: Ecto.Adapters.Postgres
end
