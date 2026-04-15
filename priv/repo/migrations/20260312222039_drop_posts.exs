defmodule DataplaneEx.Repo.Migrations.DropPosts do
  use Ecto.Migration

  def change do
    drop index(:posts, [:author_id, :inserted_at])
    drop table(:posts)
  end
end
