defmodule DataplaneEx.OpTest do
  use DataplaneEx.DataCase, async: true
  alias DataplaneEx.Op

  describe "changeset/2" do
    test "requires action and path" do
      changeset = Op.changeset(%Op{}, %{})

      refute changeset.valid?
      assert %{action: ["can't be blank"], path: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires a cid for non-delete actions" do
      changeset = Op.changeset(%Op{}, %{"action" => "create", "path" => "app.bsky.feed.post/abc"})

      refute changeset.valid?
      assert %{cid: ["can't be blank"]} = errors_on(changeset)
    end

    test "does not require a cid for delete actions" do
      changeset = Op.changeset(%Op{}, %{"action" => "delete", "path" => "app.bsky.feed.post/abc"})

      assert changeset.valid?
    end
  end
end
