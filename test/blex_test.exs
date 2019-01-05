defmodule BlexTest do
  use ExUnit.Case
  doctest Blex

  test "greets the world" do
    assert Blex.hello() == :world
  end
end
