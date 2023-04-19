defmodule HordeTaskRouterTest do
  use ExUnit.Case
  doctest HordeTaskRouter

  test "greets the world" do
    assert HordeTaskRouter.hello() == :world
  end
end
