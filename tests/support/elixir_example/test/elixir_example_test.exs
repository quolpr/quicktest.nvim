defmodule ElixirExampleTest do
  use ExUnit.Case
  doctest ElixirExample

  test "greets the world" do
    assert ElixirExample.hello() == :world
  end

  describe "other" do
    test "greets the world" do
      assert ElixirExample.hello() == :world
    end
  end
end
