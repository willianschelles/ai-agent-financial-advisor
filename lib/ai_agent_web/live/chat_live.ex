defmodule AiAgentWeb.ChatLive do
  use AiAgentWeb, :live_view

  alias AiAgent.Accounts
  alias AiAgent.LLM.RAGQuery

  def mount(_params, session, socket) do
    user = Accounts.get_user!(session["user_id"])
    
    {:ok, assign(socket, 
      query: "", 
      current_user: user, 
      messages: [],
      loading: false,
      current_action: nil,
      tool_progress: [],
      system_status: nil,
      conversation_context: []
    )}
  end

  def handle_event("submit", %{"message" => %{"content" => query}}, socket) when byte_size(query) > 0 do
    # Add user message to conversation
    user_message = create_message("user", query, "sent")
    messages = socket.assigns.messages ++ [user_message]
    
    # Create assistant message placeholder
    assistant_message = create_message("assistant", "", "thinking")
    messages = messages ++ [assistant_message]
    
    socket = assign(socket, 
      messages: messages, 
      loading: true,
      current_action: "Processing your request...",
      tool_progress: [],
      query: ""
    )

    # Send async message to self to handle the RAG query
    send(self(), {:run_rag_query, query, length(messages) - 1})

    {:noreply, socket}
  end

  def handle_event("submit", %{"message" => %{"content" => ""}}, socket) do
    {:noreply, socket}
  end

  def handle_event("clear_conversation", _params, socket) do
    {:noreply, assign(socket, 
      messages: [],
      conversation_context: [],
      system_status: "Conversation cleared"
    )}
  end

  def handle_event("retry_message", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    messages = socket.assigns.messages
    
    if index > 0 and index < length(messages) do
      # Find the user message before this assistant message
      user_message = Enum.at(messages, index - 1)
      
      if user_message && user_message.role == "user" do
        # Update assistant message to thinking state
        updated_messages = List.update_at(messages, index, fn msg ->
          %{msg | content: "", status: "thinking"}
        end)
        
        socket = assign(socket, 
          messages: updated_messages,
          loading: true,
          current_action: "Retrying..."
        )
        
        send(self(), {:run_rag_query, user_message.content, index})
        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:run_rag_query, query, message_index}, socket) do
    user = socket.assigns.current_user
    require Logger

    # Update status
    socket = assign(socket, current_action: "Searching knowledge base...")

    Logger.info("Processing query: #{query}")
    
    # Use the enhanced RAG system with tool calling capabilities
    result = case AiAgent.LLM.ToolCalling.ask_with_tools(user, query) do
      {:ok, result} ->
        Logger.info("Got result from ask_with_tools: #{inspect(result)}")
        # Format the response with enhanced feedback
        response_data = format_enhanced_response(result, query, user)
        Logger.info("Formatted response_data: #{inspect(response_data)}")
        {:ok, response_data}

      {:error, reason} ->
        if is_openai_key_error?(reason) do
          Logger.info("OpenAI API key not configured, using fallback")
          fallback = get_fallback_response(user, query)
          response_data = %{
            content: "OpenAI API key not configured.\n\n" <> fallback,
            context_sources: [],
            tools_used: [],
            status: "completed"
          }
          {:ok, response_data}
        else
          Logger.error("Error in ask_with_tools: #{reason}")
          {:error, "I encountered an error while processing your question: #{reason}"}
        end
    end

    final_socket = case result do
      {:ok, response_data} ->
        Logger.info("Updating message at index #{message_index} with response")
        # Update the assistant message with the response
        updated_messages = List.update_at(socket.assigns.messages, message_index, fn msg ->
          %{msg | 
            content: response_data.content, 
            status: "completed",
            context_sources: response_data.context_sources,
            tools_used: response_data.tools_used,
            timestamp: DateTime.utc_now()
          }
        end)
        
        Logger.info("Message updated, assigning to socket")
        
        assign(socket, 
          messages: updated_messages,
          loading: false,
          current_action: nil,
          tool_progress: [],
          system_status: "Response completed"
        )

      {:error, error_message} ->
        Logger.error("Got error, updating message with error: #{error_message}")
        # Update the assistant message with error
        updated_messages = List.update_at(socket.assigns.messages, message_index, fn msg ->
          %{msg | 
            content: error_message, 
            status: "error",
            timestamp: DateTime.utc_now()
          }
        end)
        
        assign(socket, 
          messages: updated_messages,
          loading: false,
          current_action: nil,
          tool_progress: [],
          system_status: "Error occurred"
        )
    end

    Logger.info("Returning {:noreply, final_socket}")
    {:noreply, final_socket}
  end

  # Fallback for old-style calls without message_index
  def handle_info({:run_rag_query, query}, socket) do
    handle_info({:run_rag_query, query, length(socket.assigns.messages) - 1}, socket)
  end

  # Fallback response when OpenAI is not available
  defp get_fallback_response(user, query) do
    case AiAgent.Embeddings.VectorStore.find_similar_documents(user, query, %{
           limit: 3,
           threshold: 0.5
         }) do
      {:ok, documents} when length(documents) > 0 ->
        "\n\n" <>
          Enum.map_join(documents, "\n\n", fn doc ->
            "📄 From #{doc.source} (#{doc.type}):\n#{String.slice(doc.content, 0, 200)}..."
          end)

      {:ok, []} ->
        "\n\nNo relevant documents found for '#{query}'."

      {:error, _} ->
        "\n\nCouldn't search your documents at the moment."
    end
  end

  defp create_message(role, content, status) do
    %{
      id: :crypto.strong_rand_bytes(8) |> Base.encode16(),
      role: role,
      content: content,
      status: status,
      timestamp: DateTime.utc_now(),
      context_sources: [],
      tools_used: []
    }
  end

  defp send_update_to_client(socket) do
    # Force a push to update the UI immediately
    Process.send_after(self(), :update_ui, 10)
  end

  def handle_info(:update_ui, socket) do
    {:noreply, socket}
  end

  defp build_tool_progress(tools_used) do
    Enum.map(tools_used, fn tool ->
      %{
        name: tool.name || "Unknown Tool",
        status: if(tool.success, do: "completed", else: "failed"),
        description: tool.description || "Executing action..."
      }
    end)
  end

  defp format_enhanced_response(result, _query, _user) do
    base_response = Map.get(result, :response, "No response available")

    # Extract context sources - handle different result structures
    context_used = Map.get(result, :context_used, [])
    context_sources = if is_list(context_used) and length(context_used) > 0 do
      context_used
      |> Enum.map(fn doc -> 
        if is_map(doc) do
          Map.get(doc, :source, "Unknown source")
        else
          "Unknown source"
        end
      end)
      |> Enum.uniq()
      |> Enum.take(5)
    else
      []
    end

    # Process tools - handle different result structures
    tools_from_result = Map.get(result, :tools_used, [])
    tools_used = if is_list(tools_from_result) and length(tools_from_result) > 0 do
      Enum.map(tools_from_result, fn tool ->
        if is_map(tool) do
          %{
            name: Map.get(tool, :name) || Map.get(tool, "name") || "Tool",
            success: Map.get(tool, :success) || Map.get(tool, "success") || true,
            description: Map.get(tool, :description) || Map.get(tool, "description") || "Action executed"
          }
        else
          %{
            name: "Tool",
            success: true,
            description: "Action executed"
          }
        end
      end)
    else
      []
    end

    %{
      content: base_response,
      context_sources: context_sources,
      tools_used: tools_used,
      status: "completed"
    }
  end

  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  defp is_openai_key_error?(reason) do
    reason == "OpenAI API key not configured" or 
    String.contains?(reason, "OpenAI API key not configured")
  end
end
