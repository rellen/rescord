defmodule Rescord.Repo.Migrations.AddTheErasureOfAMember do
  @moduledoc """
  The erasure of an account (ADR 0105): `users.email` may be empty, a new
  column `users.erased_at`, and a check that the email is empty exactly
  when the user is erased. Each user that is there has an email and no
  `erased_at`, so the check holds for each row, and no row changes.

  The way back (`down`) needs no erased user: a user with no email cannot
  get the old constraint `NOT NULL`.

  Written by `mix ash.codegen`, and read.
  """

  use Ecto.Migration

  def up do
    alter table(:users) do
      add :erased_at, :utc_datetime_usec
      modify :email, :citext, null: true
    end

    create constraint(:users, :email_exactly_when_not_erased,
             check: """
               (email IS NULL) = (erased_at IS NOT NULL)
             """
           )
  end

  def down do
    drop_if_exists constraint(:users, :email_exactly_when_not_erased)

    alter table(:users) do
      modify :email, :citext, null: false
      remove :erased_at
    end
  end
end
