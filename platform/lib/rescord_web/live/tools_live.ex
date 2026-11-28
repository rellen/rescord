defmodule RescordWeb.ToolsLive do
  @moduledoc """
  The tools of an organisation, at `/o/<short name>/tools`: a card for each
  tool, with a line that says what it does.

  A tool helps with a piece of work and is no record: it stores nothing.
  Each member of the organisation can open this page. A tool that fills in
  a value from the records reads it as the member.

  The dose calculator is the first tool. The next one gets a card here.
  """

  use RescordWeb, :live_view

  import RescordWeb.ToolComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Tools")}
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      ruby={@ruby?}
      section={:tools}
    >
      <.header icon={Icons.section(:tools)}>
        Tools
        <:subtitle>Aids for the work at {@organisation.name}. A tool stores nothing.</:subtitle>
      </.header>

      <.tools organisation={@organisation} />
    </Layouts.app>
    """
  end
end
