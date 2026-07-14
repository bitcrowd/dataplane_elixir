defmodule DataplaneEx.ATProto.AccountTest do
  use DataplaneEx.DataCase, async: true
  alias DataplaneEx.ATProto.Account

  describe "changeset/2" do
    test "casts required attributes" do
      attrs = %{
        "seq" => 1,
        "did" => "did:plc:alice",
        "time" => "2026-01-01T00:00:00.000Z",
        "active" => true
      }

      assert Account.changeset(%Account{}, attrs).valid?
    end

    test "requires seq, did, time and active" do
      changeset = Account.changeset(%Account{}, %{})

      refute changeset.valid?

      assert %{seq: ["can't be blank"], did: ["can't be blank"], time: ["can't be blank"]} =
               errors_on(changeset)
    end
  end

  describe "to_event/1" do
    test "builds an account event" do
      {:ok, account} =
        %Account{}
        |> Account.changeset(%{
          "seq" => 7,
          "did" => "did:plc:alice",
          "time" => "2026-01-01T00:00:00.000Z",
          "active" => true
        })
        |> Ecto.Changeset.apply_action(:validate)

      event = Account.to_event(account)

      assert event.did == "did:plc:alice"
      assert event.kind == :account
      assert event.account.seq == 7
      assert event.account.active == true
    end
  end
end
