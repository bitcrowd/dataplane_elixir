defmodule DataplaneEx.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts, primary_key: false) do
      add :id, :bigint, primary_key: true
      add :author_id, references(:users, type: :bigint), null: false
      timestamps(updated_at: false)
    end

    create index(:posts, [:author_id, :inserted_at])
  end
end
