defmodule DataplaneEx.Repo.Migrations.RecreatePostsWithAutoId do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :author_id, references(:users, type: :string), null: false
      timestamps(updated_at: false)
    end

    create index(:posts, [:author_id, :inserted_at])
  end
end
