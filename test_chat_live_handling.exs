user = AiAgent.Accounts.get_user!(1)
query = "What is the Avenua Connections?"

# Simulate what the chat live view does
result = case AiAgent.LLM.ToolCalling.ask_with_tools(user, query) do
  {:ok, result} ->
    IO.puts("Got success result")
    {:ok, result}

  {:error, reason} ->
    is_openai_error = reason == "OpenAI API key not configured" or 
                      String.contains?(reason, "OpenAI API key not configured")
    
    if is_openai_error do
      IO.puts("Detected OpenAI API key error, using fallback")
      
      # Use the fallback logic
      fallback = case AiAgent.Embeddings.VectorStore.find_similar_documents(user, query, %{
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
      
      response_data = %{
        content: "OpenAI API key not configured.\n\n" <> fallback,
        context_sources: [],
        tools_used: [],
        status: "completed"
      }
      {:ok, response_data}
    else
      IO.puts("Other error: #{reason}")
      {:error, "I encountered an error while processing your question: #{reason}"}
    end
end

IO.puts("\n=== Final Result ===")
IO.inspect(result, limit: :infinity)