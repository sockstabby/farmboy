defmodule HordeTaskRouter.Router.Runner do
  @moduledoc """
  Module which fakes deleting records from a database.
  """

  require Logger

  def execute do
    #random = :rand.uniform(1_000)

    Logger.debug("task is going to sleep")

    Process.sleep(1000*60 * 2)


    Logger.debug("task has completed")


    #Logger.info("#{__MODULE__} #{random} records deleted")
  end
end
