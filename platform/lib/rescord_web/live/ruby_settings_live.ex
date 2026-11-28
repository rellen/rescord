defmodule RescordWeb.RubySettingsLive do
  @moduledoc """
  The settings of the assistant, Ruby, in an organisation, at
  `/o/<short name>/settings/ruby` (ADR 0069): where the records go, the
  switch, the allowance of a month and the days that a conversation is
  kept. A person whose role has the power `settings` and a root user set
  them. Any other member reads that they cannot, and gets no provider and
  no setting: the policy of `Rescord.Ruby.Settings` refuses them too.

  Who turns Ruby on agrees to the place of the records. The page gives the
  action the key of the place that it showed, from the providers that it
  read when it opened, and never from the form: so nobody agrees to a
  place that the page did not show. When the root user changed the place
  in between, the action refuses, and the page shows the new place.

  A server that offers no provider has nothing to turn on, and the page
  has no form.

  The page opens again after a write.
  """

  use RescordWeb, :live_view

  import RescordWeb.RubyComponents

  alias Rescord.{Accounts, Ruby}
  alias RescordWeb.{ResidentWords, RubyWords}

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, page_title: "Ruby", problems: [])

    case Ruby.settings_for(options(socket)) do
      {:ok, settings} ->
        socket = socket |> assign(allowed?: true, settings: settings) |> read_offers()
        {:ok, assign(socket, form: fields(settings, socket.assigns))}

      {:error, :forbidden} ->
        {:ok,
         assign(socket,
           allowed?: false,
           status: Ruby.status(socket.assigns.organisation)
         )}
    end
  end

  defp options(socket),
    do: [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]

  # The providers that the server offers now, and where Ruby stands.
  defp read_offers(socket) do
    assign(socket,
      offers: Ruby.offers(options(socket)),
      status: Ruby.status(socket.assigns.organisation)
    )
  end

  # The fields of the form, as text. The provider is the one of the
  # settings while the server offers it, or the only one that it offers.
  defp fields(settings, %{offers: offers, status: status}) do
    chosen =
      case {Enum.find(offers, &(&1.id == settings.provider_id)), offers} do
        {nil, [only]} -> only
        {offer, _offers} -> offer
      end

    to_form(
      %{
        "provider_id" => if(chosen, do: chosen.id, else: ""),
        # Ruby that stopped is off: the box says what a member gets, and a
        # person who saves another field agrees to no new place.
        "enabled" => to_string(status == :on),
        "allowance" =>
          RubyWords.dollars(settings.allowance || (chosen && chosen.default_allowance)),
        "retention_days" => to_string(settings.retention_days)
      },
      as: :ruby
    )
  end

  @impl true
  def handle_event(_event, _params, %{assigns: %{allowed?: false}} = socket),
    do: {:noreply, socket}

  def handle_event("save", %{"ruby" => params}, socket) when is_map(params) do
    offer = Enum.find(socket.assigns.offers, &(&1.id == params["provider_id"]))

    result =
      with {:ok, allowance} <- allowance(params["allowance"]) do
        %{
          enabled: params["enabled"] == "true",
          allowance: allowance,
          retention_days: non_blank(params["retention_days"])
        }
        |> choose(offer)
        |> Ruby.save_settings(options(socket))
      end

    saved(socket, result, params)
  end

  # The button of a place that changed: the same provider, and the place
  # that this page shows for it.
  def handle_event("agree", _params, socket) do
    %{settings: settings, offers: offers, form: form} = socket.assigns

    case Enum.find(offers, &(&1.id == settings.provider_id)) do
      nil ->
        {:noreply, push_navigate(socket, to: path(socket))}

      offer ->
        result = %{enabled: true} |> choose(offer) |> Ruby.save_settings(options(socket))
        saved(socket, result, form.params)
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # The provider of the form, with the key of the place that this page
  # showed for it. A form with no provider of this page chooses none.
  defp choose(values, nil), do: values

  defp choose(values, offer),
    do: Map.merge(values, %{provider_id: offer.id, agreed_to: offer.place_key})

  # An empty field takes the amount that the server starts with.
  defp allowance(text) do
    case non_blank(text) do
      nil ->
        {:ok, nil}

      text ->
        with :error <- RubyWords.cents(text) do
          {:error, [{:allowance, "give an amount in US dollars, such as 20 or 0.50"}]}
        end
    end
  end

  defp saved(socket, {:ok, settings}, _params) do
    words = if settings.enabled, do: "Ruby is on.", else: "Ruby is off."

    {:noreply,
     socket
     |> put_flash(:info, "The settings of Ruby are saved. #{words}")
     |> push_navigate(to: path(socket))}
  end

  # A refusal may come from a provider that the root user changed while
  # the page was open: the page reads the providers again, so that it
  # shows the place as it is now.
  defp saved(socket, {:error, error}, params) do
    problems = if is_list(error), do: error, else: Ruby.problems(error)

    {:noreply,
     socket
     |> read_offers()
     |> assign(problems: problems, form: typed_form(params, as: :ruby))}
  end

  defp path(socket), do: ~p"/o/#{socket.assigns.organisation.short_name}/settings/ruby"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      section={:settings}
    >
      <nav aria-label="Breadcrumb">
        <.link navigate={~p"/o/#{@organisation.short_name}/settings"}>Settings</.link>
      </nav>

      <.header>
        Ruby
        <:subtitle>
          The assistant of {@organisation.name}. {RubyWords.standing(@status)}
        </:subtitle>
      </.header>

      <p :if={!@allowed?} id="ruby-refused">
        A person whose role has the power “{RescordWeb.RoleWords.power(:settings)}” sets Ruby
        up. Your role does not have it.
      </p>

      <%= if @allowed? do %>
        <p id="ruby-no-page">
          This version of Rescord has no page where a member asks Ruby yet, so no record goes
          to the service, whatever you set here. You can set Ruby up now for the version that
          has it.
        </p>

        <.problems list={general(@problems)} />

        <section :if={@offers == []} aria-labelledby="none-heading">
          <h2 id="none-heading">Nothing to turn on</h2>
          <.not_set_up :if={@status == :not_set_up} />
          <p :if={@status != :not_set_up} id="ruby-stopped" role="alert">
            {RubyWords.stopped(:provider, @organisation.name, false)}
          </p>
        </section>

        <.settings_place
          :if={@offers != []}
          organisation={@organisation}
          status={@status}
          offers={@offers}
          chosen={@form[:provider_id].value}
          agreed_on={agreed_on(@organisation, @settings)}
          problems={@problems}
        />
        <.settings_form
          :if={@offers != []}
          organisation={@organisation}
          status={@status}
          offers={@offers}
          form={@form}
          problems={@problems}
        />
      <% end %>
    </Layouts.app>
    """
  end

  # A problem with no field, or of a field that the form does not show, is
  # above the form.
  @shown [:provider_id, :agreed_to, :allowance, :retention_days]

  defp general(problems) do
    for {field, words} <- problems, field not in @shown do
      if field, do: "#{field}: #{words}", else: words
    end
  end

  # The day of the agreement, in the time zone of the organisation.
  defp agreed_on(_organisation, %{agreed_at: nil}), do: nil

  defp agreed_on(organisation, %{agreed_at: %DateTime{} = instant}),
    do: organisation |> Accounts.local_date(instant) |> ResidentWords.date()
end
