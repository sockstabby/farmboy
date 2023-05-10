import Config

config :task_router, Tasks.Repo,
  username: "postgres",
  password: "postgresSuperUserPsw",
  hostname: "mypostgres",
  database: "phoenix_react_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10


config :task_router, ecto_repos: [Tasks.Repo]

config :logger, level: :debug

config :task_router, Scheduler.Quantum,
  run_strategy: Quantum.RunStrategy.Local,
  jobs: [
  ]
