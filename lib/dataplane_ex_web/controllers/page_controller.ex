defmodule DataplaneExWeb.PageController do
  use DataplaneExWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
