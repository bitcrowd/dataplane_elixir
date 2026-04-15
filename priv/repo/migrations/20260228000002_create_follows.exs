defmodule DataplaneEx.Repo.Migrations.CreateFollows do
  use Ecto.Migration

  def change do
    create table(:follows, primary_key: false) do
      add :actor_id, references(:users, type: :bigint), null: false
      add :subject_id, references(:users, type: :bigint), null: false
    end

    create unique_index(:follows, [:actor_id, :subject_id])
    create index(:follows, [:subject_id])
  end
end
