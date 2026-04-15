defmodule DataplaneExWeb.ErrorJSONTest do
  use DataplaneExWeb.ConnCase, async: true

  test "renders 404" do
    assert DataplaneExWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert DataplaneExWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
