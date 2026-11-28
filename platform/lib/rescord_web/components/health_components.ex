defmodule RescordWeb.HealthComponents do
  @moduledoc """
  The parts of the page of the sanity checks, `/root/health` (ADR 0114):
  where the checks stand, a table of the results of the server and of each
  organisation, and what each check looks for.
  """

  use RescordWeb, :html

  alias RescordWeb.HealthWords

  @doc "Where the checks stand, and the button that runs them now."
  attr :summary, :map, required: true
  attr :running?, :boolean, required: true

  def overview(assigns) do
    ~H"""
    <section aria-labelledby="health-overview-heading">
      <h2 id="health-overview-heading">Where the checks stand</h2>
      <p id="health-summary">
        <.state kind={if @summary.fail + @summary.unknown > 0, do: "alert", else: "ok"}>
          {String.capitalize(HealthWords.summary(@summary))}.
        </.state>
        <span :if={@summary.checked_at}>The newest run was {HealthWords.time(@summary.checked_at)}.</span>
      </p>
      <p>
        A job runs the checks that are due at minute 47 of each hour. Each check reads the
        database in a transaction that cannot write, and keeps a count and some ids: never a
        name, an address or a note.
      </p>
      <p>
        The jobs themselves, and each of their tries, are in <a href={~p"/root/oban"}>Oban Web</a>.
      </p>
      <button type="button" phx-click="run" disabled={@running?}>
        {if @running?, do: "Running each check", else: "Run each check now"}
      </button>
    </section>
    """
  end

  @doc "The results of the server, or of one organisation, as a table."
  attr :organisation, :map, default: nil
  attr :rows, :list, required: true

  def results(assigns) do
    assigns =
      assign(assigns,
        title:
          if(assigns.organisation,
            do: "#{assigns.organisation.name} (#{assigns.organisation.short_name})",
            else: "The server"
          ),
        key: if(assigns.organisation, do: assigns.organisation.id, else: "server")
      )

    ~H"""
    <section aria-labelledby={"health-#{@key}-heading"}>
      <h2 id={"health-#{@key}-heading"}>{@title}</h2>
      <table>
        <caption>The checks of {@title}</caption>
        <thead>
          <tr>
            <th scope="col">Check</th>
            <th scope="col">State</th>
            <th scope="col">Found</th>
            <th scope="col">Since</th>
            <th scope="col">Last run</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows}>
            <th scope="row">{Rescord.Health.describe(row.check).title}</th>
            <td>
              <.state kind={elem(HealthWords.level(row.level), 0)}>
                {elem(HealthWords.level(row.level), 1)}
              </.state>
            </td>
            <td>
              {row.count}
              <details :if={row.ids != []}>
                <summary>Ids</summary>
                <ul>
                  <li :for={id <- row.ids}><code>{id}</code></li>
                </ul>
              </details>
            </td>
            <td>{HealthWords.time(row.since)}</td>
            <td>{HealthWords.time(row.checked_at)}</td>
          </tr>
        </tbody>
      </table>
    </section>
    """
  end

  @doc "What each check looks for, how often it runs, and what a fault means."
  attr :checks, :list, required: true

  def checks(assigns) do
    ~H"""
    <section aria-labelledby="health-checks-heading">
      <h2 id="health-checks-heading">What the checks look for</h2>
      <dl>
        <%= for check <- @checks do %>
          <dt>{check.title}</dt>
          <dd>
            {HealthWords.cadence(check.cadence)}, {if check.scope == :server,
              do: "for the server",
              else: "for each organisation"}. {check.explain}
          </dd>
        <% end %>
      </dl>
    </section>
    """
  end
end
