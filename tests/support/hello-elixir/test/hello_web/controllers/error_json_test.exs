defmodule HelloWeb.ErrorJSONTest do
  use HelloWeb.ConnCase, async: true

  test "renders 404" do
    assert HelloWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    IO.puts("renders 500")

    assert HelloWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end

  describe "other" do
    test "renders 500" do
      IO.puts("other -> renders 500")

      assert HelloWeb.ErrorJSON.render("500.json", %{}) ==
               %{errors: %{detail: "Internal Server Error"}}
    end

    test "renders 404" do
      IO.puts("other -> renders 404")

      assert HelloWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
    end
  end
end
