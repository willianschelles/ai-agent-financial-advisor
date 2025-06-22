defmodule AiAgent.LLM.RAGQuery do
  @moduledoc """
  Complete RAG (Retrieval-Augmented Generation) query system.

  This module implements the full RAG pipeline:
  1. Embed the user question using OpenAI embeddings
  2. Find top-N most similar documents using pgvector cosine similarity
  3. Combine user question + relevant docs as context for LLM
  4. Call OpenAI with the enhanced context to generate a response
  """

  require Logger

  alias AiAgent.Embeddings
  alias AiAgent.Embeddings.VectorStore
  alias AiAgent.User

  @openai_chat_url "https://api.openai.com/v1/chat/completions"
  @default_model "gpt-4o"
  @default_max_tokens 1000

  @doc """
  Main RAG query function. Takes a user question and returns an LLM response
  enhanced with relevant document context.

  ## Parameters
  - user: User struct (for retrieving their documents)
  - question: The user's question/query
  - opts: Options map with keys:
    - :model - OpenAI model to use (default: "gpt-4o") 
    - :max_tokens - Max response tokens (default: 1000)
    - :context_limit - Max number of documents to retrieve (default: 5)
    - :similarity_threshold - Min similarity for document inclusion (default: 0.6)
    - :temperature - LLM creativity (default: 0.7)
    - :system_prompt - Custom system prompt (optional)

  ## Returns
  - {:ok, %{response: string, context_used: [docs], metadata: map}} on success
  - {:error, reason} on failure

  ## Example
      iex> AiAgent.LLM.RAGQuery.ask(user, "Who mentioned their kid plays baseball?")
      {:ok, %{
        response: "Based on your emails, John Smith mentioned that his kid plays baseball...",
        context_used: [%{content: "...", source: "john@example.com", similarity: 0.85}],
        metadata: %{documents_found: 3, model_used: "gpt-4o"}
      }}
  """
  def ask(user, question, opts \\ %{}) when is_binary(question) do
    Logger.info("RAG Query from user #{user.id}: #{String.slice(question, 0, 100)}...")

    # Extract options with defaults
    model = Map.get(opts, :model, @default_model)
    max_tokens = Map.get(opts, :max_tokens, @default_max_tokens)
    context_limit = Map.get(opts, :context_limit, 5)
    # Lowered from 0.6 to 0.3
    similarity_threshold = Map.get(opts, :similarity_threshold, 0.3)
    temperature = Map.get(opts, :temperature, 0.7)
    system_prompt = Map.get(opts, :system_prompt)

    with {:ok, relevant_docs} <-
           retrieve_relevant_context(user, question, context_limit, similarity_threshold),
         {:ok, llm_response} <-
           query_llm_with_context(
             question,
             relevant_docs,
             model,
             max_tokens,
             temperature,
             system_prompt
           ) do
      result = %{
        response: llm_response,
        context_used: relevant_docs,
        metadata: %{
          documents_found: length(relevant_docs),
          model_used: model,
          similarity_threshold: similarity_threshold,
          question_length: String.length(question)
        }
      }

      Logger.info("RAG Query completed successfully. Used #{length(relevant_docs)} documents.")
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("RAG Query failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Retrieve relevant document context for a question using vector similarity search.

  ## Parameters
  - user: User struct
  - question: The question to find context for
  - limit: Maximum number of documents to return
  - threshold: Minimum similarity threshold

  ## Returns
  - {:ok, [documents]} - List of relevant documents with similarity scores
  - {:error, reason} - Error message
  """
  def retrieve_relevant_context(user, question, limit \\ 5, threshold \\ 0.3) do
    Logger.debug("Retrieving context for question: #{String.slice(question, 0, 100)}...")

    search_opts = %{
      limit: limit,
      threshold: threshold
    }

    case VectorStore.find_similar_documents(user, question, search_opts) do
      {:ok, documents} ->
        Logger.info("Found #{length(documents)} relevant documents")

        # Add some metadata to each document
        enhanced_docs =
          Enum.map(documents, fn doc ->
            Map.put(doc, :context_preview, String.slice(doc.content, 0, 150) <> "...")
          end)

        {:ok, enhanced_docs}

      {:error, reason} ->
        Logger.error("Failed to retrieve context: #{inspect(reason)}")
        {:error, "Failed to retrieve relevant documents: #{reason}"}
    end
  end

  @doc """
  Query the LLM with enhanced context from relevant documents.

  ## Parameters
  - question: Original user question
  - relevant_docs: List of relevant documents from vector search
  - model: OpenAI model to use
  - max_tokens: Maximum response tokens
  - temperature: Response creativity
  - custom_system_prompt: Optional custom system prompt

  ## Returns
  - {:ok, response_text} on success
  - {:error, reason} on failure
  """
  def query_llm_with_context(
        question,
        relevant_docs,
        model,
        max_tokens,
        temperature,
        custom_system_prompt \\ nil
      ) do
    Logger.debug("Querying LLM with #{length(relevant_docs)} context documents")

    # Build the context from relevant documents
    context = build_document_context(relevant_docs)

    # Build the prompt
    messages = build_rag_prompt(question, context, custom_system_prompt)

    # Call OpenAI
    case call_openai_chat(messages, model, max_tokens, temperature) do
      {:ok, response} ->
        Logger.info("LLM response generated successfully (#{String.length(response)} chars)")
        {:ok, response}

      {:error, reason} ->
        Logger.error("LLM query failed: #{inspect(reason)}")
        {:error, "Failed to generate response: #{reason}"}
    end
  end

  @doc """
  Quick RAG query function for simple use cases.
  Returns just the response text without metadata.

  ## Example
      iex> AiAgent.LLM.RAGQuery.quick_ask(user, "What did John say about baseball?")
      "Based on your emails, John mentioned that his son plays little league baseball..."
  """
  def quick_ask(user, question, opts \\ %{}) do
    case ask(user, question, opts) do
      {:ok, %{response: response}} ->
        response

      {:error, reason} ->
        "I couldn't find relevant information to answer that question. Error: #{reason}"
    end
  end

  @doc """
  Get just the relevant context for a question without calling the LLM.
  Useful for debugging or building custom prompts.
  """
  def get_context_only(user, question, opts \\ %{}) do
    limit = Map.get(opts, :limit, 5)
    threshold = Map.get(opts, :threshold, 0.6)

    case retrieve_relevant_context(user, question, limit, threshold) do
      {:ok, docs} ->
        context = build_document_context(docs)
        {:ok, %{context: context, documents: docs}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp build_document_context(documents) when is_list(documents) do
    if Enum.empty?(documents) do
      "No relevant documents found."
    else
      documents
      |> Enum.with_index(1)
      |> Enum.map(fn {doc, index} ->
        """
        Document #{index} (#{doc.type} from #{doc.source}, similarity: #{Float.round(doc.similarity, 3)}):
        #{doc.content}
        """
      end)
      |> Enum.join("\n---\n")
    end
  end

  defp build_rag_prompt(question, context, custom_system_prompt) do
    system_prompt = custom_system_prompt || build_default_system_prompt()

    user_prompt = """
    CONTEXT DOCUMENTS:
    #{context}

    USER QUESTION: #{question}

    Please answer the user's question based on the context documents provided above. If the context doesn't contain relevant information to answer the question, please say so clearly. Be specific and cite information from the documents when possible.
    """

    [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_prompt}
    ]
  end

  defp build_default_system_prompt do
    """
    You are an AI assistant helping a financial advisor with their client information. You have access to their emails, CRM contacts, and notes.

    Your role is to:
    1. Answer questions about clients based on the provided context documents
    2. Help find specific information from emails and CRM records
    3. Provide clear, accurate responses based only on the available information
    4. Indicate when you don't have enough information to answer a question

    Guidelines:
    - Be concise but thorough in your responses
    - Always base your answers on the provided context documents
    - If asked about specific people or events, cite the relevant document/email
    - If the context doesn't contain the needed information, say so clearly
    - Maintain professional tone appropriate for a financial advisor's assistant
    """
  end

  defp call_openai_chat(messages, model, max_tokens, temperature) do
    case get_openai_key() do
      nil ->
        {:error, "OpenAI API key not configured"}

      api_key ->
        headers = [
          {"Authorization", "Bearer #{api_key}"},
          {"Content-Type", "application/json"}
        ]

        payload = %{
          model: model,
          messages: messages,
          max_tokens: max_tokens,
          temperature: temperature
        }

        Logger.debug("Calling OpenAI Chat API with model: #{model}")

        case Req.post(@openai_chat_url, headers: headers, json: payload) do
          {:ok,
           %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
            {:ok, String.trim(content)}

          {:ok, %{status: status, body: body}} ->
            Logger.error("OpenAI Chat API error: #{status} - #{inspect(body)}")
            {:error, "OpenAI API error: #{status}"}

          {:error, reason} ->
            Logger.error("Failed to call OpenAI Chat API: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end
    end
  end

  defp get_openai_key do
    System.get_env("OPENAI_API_KEY")
  end
end
