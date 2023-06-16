defmodule FarmboyTest do
  use ExUnit.Case
  doctest Farmboy

  test "greets the world" do
    assert Farmboy.hello() == :world
  end
end
