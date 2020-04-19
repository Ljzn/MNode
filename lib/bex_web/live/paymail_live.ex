defmodule BexWeb.PaymailLive do
  @moduledoc """
  Parse paymail
  """
  use Phoenix.LiveView
  require Logger
  alias BexWeb.Router.Helpers, as: Routes

  def mount(_session, socket) do
    {:ok,
     socket
     |> assign(:paymail, false)
     |> assign(:loading, false)}
  end

  def handle_params(%{"mail" => mail}, _url, socket) do
    handle_event("submit", %{"mail" => mail}, socket)
  end

  def handle_params(_, _url, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    ~L"""
    <h2>Paymail</h2>
    <%= if @loading do %>
    <h4>Loading...</h4>
    <% end %>

    <form phx-submit="submit">
      <input name="mail">Enter your paymail</input>
      <button type="submit">Parse</button>
    </form>

    <%= if @paymail do %>
      <h1><%= @paymail.nickname %></h1>
      <img src="<%= Routes.static_path(BexWeb.Endpoint, "/mnode/" <> Path.basename(@paymail.avatar_path)) %>">
      <h2><%= @paymail.username <> "@" <> @paymail.host %></h2>
    <% end %>
    """
  end

  def handle_event("submit", %{"mail" => m}, socket) do
    send(self(), {:parse, m})
    {:noreply, assign(socket, :loading, true)}
  end

  def handle_info({:parse, m}, socket) do
    paymail = Paymail.parse(m)

    {:noreply,
     assign(socket, :loading, false)
     |> assign(:paymail, paymail)}
  end
end
