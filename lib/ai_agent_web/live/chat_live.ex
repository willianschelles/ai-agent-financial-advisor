defmodule AiAgentWeb.ChatLive do
  use AiAgentWeb, :live_view
  alias AiAgent.Context.Chat
  alias AiAgent.Accounts

  def mount(_params, session, socket) do
    user = Accounts.get_user!(session["user_id"])
    {:ok, assign(socket, query: "", response: nil, current_user: user)}
  end

  def handle_event("submit", %{"query" => query}, socket) do
    # response = Chat.ask(socket.assigns.current_user, query)
    response = "all good man"
    {:noreply, assign(socket, response: response, query: "")}
  end
end
