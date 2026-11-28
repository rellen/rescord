defmodule RescordWeb.RootUsageLive do
  @moduledoc """
  The usage counts of the server, for a root user, at `/root/usage`
  (ADR 0098): where the counts stand, where they go, the token of the
  address, "Send a test", the exact document that a send writes, the counts
  of the last 30 days, and the installation id. The live session lets only
  a root user in, and the policies refuse each other person.

  No setting of the counts is in the environment (ADR 0068): this page is
  where they are set. The token goes from its form to the action and
  nowhere else: no assign holds it, and the page never sends one back.

  "Send a test" runs in a task of the page, so the page answers while the
  address does.
  """

  use RescordWeb, :live_view

  import RescordWeb.UsageComponents

  alias Rescord.Usage

  @days 30

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Usage counts", problems: [], token_problems: [], testing?: false)
     |> load()}
  end

  defp load(socket) do
    actor = socket.assigns.current_user
    settings = Usage.settings(actor: actor)
    today = Date.utc_today()
    day = Usage.last_full_day(today, actor: actor)
    counts = if day, do: Usage.counts_of(day, actor: actor), else: []

    assign(socket,
      settings: settings,
      form: settings_form_of(settings),
      day: day,
      document: Usage.document(settings, day || Date.add(today, -1), counts),
      features: features(Usage.counts_since(Date.add(today, 1 - @days), actor: actor))
    )
  end

  defp settings_form_of(settings) do
    to_form(
      %{
        "mode" => to_string(settings.mode),
        "format" => to_string(settings.format),
        "endpoint" => settings.endpoint || ""
      },
      as: :usage
    )
  end

  # The rows of the table: each feature with its sums by kind, and its
  # items, most used first.
  defp features(counts) do
    counts
    |> Enum.group_by(& &1.feature)
    |> Enum.map(fn {feature, rows} ->
      sums =
        Enum.reduce(
          rows,
          %{page: 0, action: 0, file: 0},
          &Map.update!(&2, &1.kind, fn n -> n + &1.count end)
        )

      items =
        rows
        |> Enum.group_by(&{&1.kind, &1.item}, & &1.count)
        |> Enum.map(fn {{kind, item}, numbers} -> {kind, item, Enum.sum(numbers)} end)
        |> Enum.sort_by(fn {kind, item, count} -> {-count, kind, item} end)

      Map.merge(sums, %{feature: feature, items: items})
    end)
    |> Enum.sort_by(&{-(&1.page + &1.action + &1.file), &1.feature})
  end

  @impl true
  def handle_event("save", %{"usage" => params}, socket) when is_map(params) do
    attributes = %{
      mode: choice(params["mode"], [:off, :local, :send]),
      format: choice(params["format"], [:otlp, :json]),
      endpoint: blank_to_nil(params["endpoint"])
    }

    case Usage.save_settings(attributes, actor: socket.assigns.current_user) do
      {:ok, _settings} ->
        {:noreply, socket |> assign(problems: []) |> put_flash(:info, "Saved.") |> load()}

      {:error, error} ->
        {:noreply,
         assign(socket,
           problems: Usage.problems(error),
           form: to_form(params, as: :usage)
         )}
    end
  end

  def handle_event("save_token", %{"usage" => %{"token" => token}}, socket)
      when is_binary(token) do
    case Usage.save_token(token, actor: socket.assigns.current_user) do
      {:ok, _settings} ->
        {:noreply,
         socket |> assign(token_problems: []) |> put_flash(:info, "The token is saved.") |> load()}

      {:error, error} ->
        problems =
          Enum.map(Usage.problems(error), fn
            {:endpoint, words} -> {:token, words}
            {nil, words} -> {:token, words}
            problem -> problem
          end)

        {:noreply, assign(socket, token_problems: problems)}
    end
  end

  def handle_event("forget_token", _params, socket) do
    with %{installation_id: id} = settings when is_binary(id) <- socket.assigns.settings,
         {:ok, _settings} <- Usage.forget_token(settings, actor: socket.assigns.current_user) do
      {:noreply, socket |> put_flash(:info, "The token is deleted.") |> load()}
    else
      _other -> {:noreply, socket}
    end
  end

  def handle_event("test", _params, socket) do
    if socket.assigns.testing? do
      {:noreply, socket}
    else
      actor = socket.assigns.current_user

      {:noreply,
       socket
       |> assign(testing?: true)
       |> start_async(:test, fn -> Usage.send_test(actor: actor) end)}
    end
  end

  def handle_event("new_installation", _params, socket) do
    case Usage.renew_installation(actor: socket.assigns.current_user) do
      {:ok, _settings} ->
        {:noreply, socket |> put_flash(:info, "This installation has a new id.") |> load()}

      {:error, _error} ->
        {:noreply, socket}
    end
  end

  def handle_event("forget_counts", _params, socket) do
    case Usage.forget_counts(actor: socket.assigns.current_user) do
      :ok -> {:noreply, socket |> put_flash(:info, "Each count is deleted.") |> load()}
      {:error, _error} -> {:noreply, put_flash(socket, :error, "The counts were not deleted.")}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:test, {:ok, {:ok, _settings}}, socket) do
    {:noreply, socket |> assign(testing?: false) |> load()}
  end

  def handle_async(:test, _failed, socket) do
    {:noreply,
     socket
     |> assign(testing?: false)
     |> put_flash(:error, "The test did not run. Save an address, and try again.")}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # A value of a fixed list, from the text of the form. Never an atom made
  # from what a browser sent.
  defp choice(value, choices), do: Enum.find(choices, &(to_string(&1) == value))

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp blank_to_nil(_value), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} section={:root}>
      <.header>
        Usage counts
        <:subtitle>Which features the rescues on this server use, and where the counts go.</:subtitle>
      </.header>

      <p><a href={~p"/root"}>Back to the page of the server</a></p>

      <.status settings={@settings} />
      <.settings_form form={@form} problems={@problems} />
      <.token_and_test settings={@settings} problems={@token_problems} testing?={@testing?} />
      <.document settings={@settings} day={@day} document={@document} />
      <.counts features={@features} />
      <.installation settings={@settings} />
    </Layouts.app>
    """
  end
end
