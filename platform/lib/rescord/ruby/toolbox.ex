defmodule Rescord.Ruby.Toolbox do
  @moduledoc """
  The options of `AshAi.ToolLoop` for one member in one organisation
  (ADR 0069): who acts, which tools, and how each request goes out.

    * The actor is the member, made by `Rescord.Ruby.Actor.for/1`, so the
      level of a root user is off in each tool call. No tool call passes
      `authorize?: false`.
    * The tools are the names of `Rescord.Ruby.Catalogue`, always a list.
      A digest is there only for a person who may read what it reads.
    * Each request goes through `Rescord.Ruby.LLM.Client`, with the
      options of the profile: the key, the limit of an answer, the effort
      and the prompt cache.

  The options hold the key of the provider. Never log them, and never
  keep them.
  """

  alias Rescord.Accounts.User
  alias Rescord.Ruby.{Actor, Catalogue}
  alias Rescord.Ruby.LLM.{Client, Profile}

  # The most requests of one turn: a question, and the reads that answer it.
  @max_iterations 8

  @doc """
  The options for this member. `profile` is the profile of the provider of
  the organisation, from `Rescord.Ruby.LLM.profile_of/1`. `extra` adds to
  the options, such as the system prompt.
  """
  @spec options(User.t(), term, Profile.t(), keyword) :: keyword
  def options(%User{} = user, tenant, %Profile{} = profile, extra \\ []) do
    actor = Actor.for(user)
    entries = Catalogue.on(Rescord.Ruby.settings(tenant), profile)

    [
      otp_app: :rescord,
      actor: actor,
      tenant: tenant,
      # Always a list of names. Never `true`.
      tools: for(%{source: :action, name: name} <- entries, do: name),
      extra_tools:
        for(
          %{source: {:extra, module}} <- entries,
          module.available?(actor, tenant),
          do: module.tool()
        ),
      model: Profile.model_spec(profile),
      # Always `Client`: it counts the tokens of each request.
      req_llm: Client,
      # Without them a request has no key and no cache, and ReqLLM asks for
      # the whole output limit of the model.
      req_llm_opts: Profile.req_llm_opts(profile),
      max_iterations: @max_iterations
    ] ++ extra
  end
end
