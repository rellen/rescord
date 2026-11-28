defmodule Rescord.Repo.TenantMigrations.AddRubyConversations do
  @moduledoc """
  Adds the tables of the conversations with the assistant and of their
  messages (ADR 0069) to the schema of an organisation. Both are new and
  empty, and no other table changes.

  A message goes with its conversation, and a reply with the message that
  it answers: each reference deletes with its row, so that the removal of
  a conversation is one statement.

  `mix ash_postgres.generate_migrations` wrote the statements.
  """

  use Ecto.Migration

  def up do
    create table(:ruby_messages, primary_key: false, prefix: prefix()) do
      add :id, :uuid, null: false, default: fragment("uuidv7()"), primary_key: true
      add :owner_id, :uuid, null: false
      add :source, :text, null: false
      add :text, :text, null: false, default: ""
      add :header, :text
      add :parts, {:array, :map}, null: false, default: []
      add :prompt_fingerprint, :text
      add :state, :text
      add :reason, :text
      add :resume_requested, :boolean, null: false, default: false
      add :stop_requested, :boolean, null: false, default: false
      add :model, :text
      add :usage, :map
      add :cost_microdollars, :bigint
      add :rating, :text
      add :rating_note, :text

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :conversation_id, :uuid, null: false

      add :response_to_id,
          references(:ruby_messages,
            column: :id,
            name: "ruby_messages_response_to_id_fkey",
            type: :uuid,
            prefix: prefix(),
            on_delete: :delete_all
          )
    end

    create unique_index(:ruby_messages, [:response_to_id], name: "ruby_messages_one_reply_index")

    create index(:ruby_messages, [:conversation_id, :id])

    create table(:ruby_conversations, primary_key: false, prefix: prefix()) do
      add :id, :uuid, null: false, default: fragment("uuidv7()"), primary_key: true
    end

    alter table(:ruby_messages, prefix: prefix()) do
      modify :conversation_id,
             references(:ruby_conversations,
               column: :id,
               name: "ruby_messages_conversation_id_fkey",
               type: :uuid,
               prefix: prefix(),
               on_delete: :delete_all
             )
    end

    alter table(:ruby_conversations, prefix: prefix()) do
      add :owner_id, :uuid, null: false
      add :title, :text
      add :about, :text
      add :last_message_at, :utc_datetime_usec, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:ruby_conversations, [:owner_id, :last_message_at])
  end

  def down do
    drop_if_exists index(:ruby_conversations, [:owner_id, :last_message_at])

    alter table(:ruby_conversations, prefix: prefix()) do
      remove :updated_at
      remove :inserted_at
      remove :last_message_at
      remove :about
      remove :title
      remove :owner_id
    end

    drop constraint(:ruby_messages, "ruby_messages_response_to_id_fkey")

    drop constraint(:ruby_messages, "ruby_messages_conversation_id_fkey")

    alter table(:ruby_messages, prefix: prefix()) do
      modify :conversation_id, :uuid
    end

    drop table(:ruby_conversations, prefix: prefix())

    drop_if_exists index(:ruby_messages, [:conversation_id, :id])

    drop_if_exists unique_index(:ruby_messages, [:response_to_id],
                     name: "ruby_messages_one_reply_index"
                   )

    drop table(:ruby_messages, prefix: prefix())
  end
end
