defmodule AiAgentWeb.ChatLive do
  use AiAgentWeb, :live_view

  alias AiAgent.Accounts
  alias AiAgent.LLM.RAGQuery

  def mount(_params, session, socket) do
    user = Accounts.get_user!(session["user_id"])
    {:ok, assign(socket, query: "", response: nil, current_user: user, loading: false)}
  end

  def handle_event("submit", %{"query" => query}, socket) when byte_size(query) > 0 do
    # Set loading state
    socket = assign(socket, loading: true, query: query)

    # Send async message to self to handle the RAG query
    send(self(), {:run_rag_query, query})

    {:noreply, socket}
  end

  def handle_event("submit", %{"query" => ""}, socket) do
    # Empty query, don't do anything
    {:noreply, socket}
  end

  def handle_info({:run_rag_query, query}, socket) do
    user = socket.assigns.current_user

    # Use the RAG system to get a response
    response = case RAGQuery.ask(user, query) do
      {:ok, result} ->
        # Format the response with context information
        context_info = if length(result.context_used) > 0 do
          sources = result.context_used
                   |> Enum.map(& &1.source)
                   |> Enum.uniq()
                   |> Enum.take(3)
          "\n\n Based on information from: #{Enum.join(sources, ", ")}"
        else
          "\n\n No relevant documents found in your data."
        end

        result.response <> context_info

      {:error, "OpenAI API key not configured"} ->
        """
        OpenAI API key not configured.

        To use the AI features, please set your OPENAI_API_KEY environment variable.

        For now, here's what I found in your documents about "#{query}":
        """ <> get_fallback_response(user, query)

      {:error, reason} ->
        "I encountered an error while processing your question: #{reason}"
    end

    socket = assign(socket, response: response, loading: false, query: "")
    {:noreply, socket}
  end

  # Fallback response when OpenAI is not available
  defp get_fallback_response(user, query) do
    case AiAgent.Embeddings.VectorStore.find_similar_documents(user, query, %{limit: 3, threshold: 0.5}) do
      {:ok, documents} when length(documents) > 0 ->
        "\n\n" <> Enum.map_join(documents, "\n\n", fn doc ->
          "📄 From #{doc.source} (#{doc.type}):\n#{String.slice(doc.content, 0, 200)}..."
        end)

      {:ok, []} ->
        "\n\nNo relevant documents found for '#{query}'."

      {:error, _} ->
        "\n\nCouldn't search your documents at the moment."
    end
  end
end
