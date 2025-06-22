defmodule AiAgent.Embeddings.RAG do
  @moduledoc """
  RAG (Retrieval-Augmented Generation) module that combines the embeddings and vector store
  functionality to provide context for LLM queries.
  """

  alias AiAgent.Embeddings.VectorStore
  alias AiAgent.Embeddings.DataIngestion

  @doc """
  Get RAG context for a user query. This is the main function used by the chat system.

  ## Parameters
  - user: User struct
  - query: User's question/query text
  - opts: Options for context retrieval
    - :limit - Maximum number of documents to retrieve (default: 5)
    - :threshold - Similarity threshold (default: 0.6)
    - :types - Filter by document types

  ## Returns
  - {:ok, context_string} - Formatted context for the LLM
  - {:error, reason} - Error message
  """
  def get_context(user, query, opts \\ %{}) do
    default_opts = %{limit: 5, threshold: 0.6}
    search_opts = Map.merge(default_opts, opts)

    case VectorStore.get_rag_context(user, query, search_opts) do
      {:ok, ""} ->
        {:ok, "No relevant context found for this query."}

      {:ok, context} ->
        formatted_context = """
        RELEVANT CONTEXT:
        #{context}

        Please use this context to help answer the user's question. If the context doesn't contain relevant information, please indicate that.
        """

        {:ok, formatted_context}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Initialize RAG for a user by ingesting their data.
  This should be called after OAuth setup to populate the vector store.

  ## Parameters
  - user: User struct with OAuth tokens
  - opts: Ingestion options

  ## Returns
  - {:ok, %{gmail: count, hubspot: count}} - Number of documents ingested
  - {:error, reason} - Error message
  """
  def initialize_for_user(user, opts \\ %{}) do
    DataIngestion.ingest_all_data(user, opts)
    |> IO.inspect(label: "RAG Initialization Result")
  end

  @doc """
  Refresh data for a user by re-ingesting recent data.
  This can be called periodically or triggered by webhooks.

  ## Parameters
  - user: User struct
  - opts: Options with optional keys:
    - :clear_existing - Whether to clear existing data first (default: false)
    - :gmail_opts - Options for Gmail ingestion
    - :hubspot_opts - Options for HubSpot ingestion

  ## Returns
  - {:ok, %{gmail: count, hubspot: count}} - Number of new documents ingested
  - {:error, reason} - Error message
  """
  def refresh_user_data(user, opts \\ %{}) do
    clear_existing = Map.get(opts, :clear_existing, false)

    # Clear existing data if requested
    if clear_existing do
      VectorStore.delete_documents(user, %{})
    end

    # Re-ingest data
    DataIngestion.ingest_all_data(user, opts)
  end

  @doc """
  Get statistics about a user's RAG data.
  Useful for debugging and user dashboards.
  """
  def get_user_stats(user) do
    VectorStore.get_document_stats(user)
  end

  @doc """
  Search for specific information in a user's data.
  More targeted than general RAG context.

  ## Parameters
  - user: User struct
  - search_terms: Specific terms to search for
  - opts: Search options

  ## Returns
  - {:ok, [results]} - List of matching documents with similarity scores
  - {:error, reason} - Error message
  """
  def search(user, search_terms, opts \\ %{}) do
    VectorStore.find_similar_documents(user, search_terms, opts)
  end

  @doc """
  Answer a specific question about a client or topic.
  This is used for queries like "Who mentioned their kid plays baseball?"

  ## Parameters
  - user: User struct
  - question: Specific question to answer
  - opts: Search options

  ## Returns
  - {:ok, answer_context} - Context that should contain the answer
  - {:error, reason} - Error message
  """
  def answer_question(user, question, opts \\ %{}) do
    # Use higher similarity threshold for specific questions
    search_opts = Map.merge(%{limit: 10, threshold: 0.5}, opts)

    case VectorStore.find_similar_documents(user, question, search_opts) do
      {:ok, []} ->
        {:ok, "I couldn't find any relevant information to answer that question."}

      {:ok, documents} ->
        # Format the results to highlight the most relevant information
        formatted_results =
          documents
          # Take top 5 results
          |> Enum.take(5)
          |> Enum.map(fn doc ->
            """
            FROM: #{doc.source} (#{doc.type})
            SIMILARITY: #{Float.round(doc.similarity, 3)}
            CONTENT: #{doc.content}
            """
          end)
          |> Enum.join("\n---\n")

        answer_context = """
        Based on your data, here are the most relevant matches for "#{question}":

        #{formatted_results}

        Please analyze this information to answer the user's question.
        """

        {:ok, answer_context}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
