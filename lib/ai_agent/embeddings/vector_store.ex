defmodule AiAgent.Embeddings.VectorStore do
  @moduledoc """
  Vector store operations using pgvector for storing and retrieving document embeddings.
  Handles document storage, similarity search, and RAG (Retrieval-Augmented Generation) queries.
  """

  import Ecto.Query
  require Logger

  alias AiAgent.Repo
  alias AiAgent.Document
  alias AiAgent.User
  alias AiAgent.Embeddings

  @doc """
  Store a document with its embedding in the vector database.

  ## Parameters
  - user: User struct or user_id
  - content: Text content to store
  - source: Source of the document (email address, "hubspot", etc.)
  - type: Type of document ("email", "hubspot_note", "hubspot_contact", etc.)
  - metadata: Optional map with additional metadata

  ## Returns
  - {:ok, document} on success
  - {:error, reason} on failure
  """
  def store_document(user, content, source, type, metadata \\ %{}) do
    user_id = get_user_id(user)

    with {:ok, embedding} <- Embeddings.embed_text(content),
         {:ok, document} <- create_document(user_id, content, source, type, embedding, metadata) do
      Logger.info("Stored document: user_id=#{user_id}, type=#{type}, source=#{source}")
      {:ok, document}
    else
      {:error, reason} ->
        Logger.error("Failed to store document: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Store multiple documents in batch. More efficient for large datasets.

  ## Parameters
  - user: User struct or user_id
  - documents: List of maps with keys: :content, :source, :type, :metadata (optional)

  ## Returns
  - {:ok, [documents]} on success
  - {:error, reason} on failure
  """
  def store_documents_batch(user, documents) when is_list(documents) do
    Logger.debug(
      "store_documents_batch/2 called with user=#{inspect(user)} and documents count=#{length(documents)}"
    )

    user_id = get_user_id(user)

    # Extract content for batch embedding
    contents = Enum.map(documents, & &1.content)

    with {:ok, embeddings} <- Embeddings.embed_texts(contents) do
      # Create document structs with embeddings
      document_params =
        documents
        |> Enum.zip(embeddings)
        |> Enum.map(fn {doc, embedding} ->
          %{
            user_id: user_id,
            content: doc.content,
            source: doc.source,
            type: doc.type,
            embedding: embedding,
            inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
            updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
          }
        end)

      # Batch insert
      case Repo.insert_all(Document, document_params, returning: true) do
        {_count, documents} ->
          Logger.info("Batch stored #{length(documents)} documents for user_id=#{user_id}")
          {:ok, documents}

        error ->
          Logger.error("Failed to batch insert documents: #{inspect(error)}")
          {:error, "Database insertion failed"}
      end
    else
      {:error, reason} ->
        Logger.error("Failed to generate embeddings for batch: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Find similar documents using vector similarity search.

  ## Parameters
  - user: User struct or user_id
  - query_text: Text to search for
  - opts: Options map with optional keys:
    - :limit - Maximum number of results (default: 10)
    - :threshold - Minimum similarity threshold (default: 0.7)
    - :types - List of document types to filter by
    - :sources - List of sources to filter by

  ## Returns
  - {:ok, [documents_with_similarity]} on success
  - {:error, reason} on failure
  """
  # cosine similarity in pgvector is calculated as 1 - (a <=> b)
  def find_similar_documents(user, query_text, opts \\ %{}) do
    user_id = get_user_id(user)
    limit = Map.get(opts, :limit, 10)
    # Lowered from 0.7 to 0.3 for better recall
    threshold = Map.get(opts, :threshold, 0.3)
    types = Map.get(opts, :types, [])
    sources = Map.get(opts, :sources, [])

    with {:ok, query_embedding} <- Embeddings.embed_text(query_text) do
      query =
        from(d in Document,
          where: d.user_id == ^user_id,
          where: fragment("1 - (? <=> ?)", d.embedding, ^query_embedding) >= ^threshold,
          select: %{
            id: d.id,
            content: d.content,
            source: d.source,
            type: d.type,
            inserted_at: d.inserted_at,
            similarity: fragment("1 - (? <=> ?)", d.embedding, ^query_embedding)
          },
          order_by: [desc: fragment("1 - (? <=> ?)", d.embedding, ^query_embedding)],
          limit: ^limit
        )

      # Add type filter if specified
      query =
        if Enum.empty?(types) do
          query
        else
          from(d in query, where: d.type in ^types)
        end

      # Add source filter if specified
      query =
        if Enum.empty?(sources) do
          query
        else
          from(d in query, where: d.source in ^sources)
        end

      results = Repo.all(query)

      Logger.info("Found #{length(results)} similar documents for user_id=#{user_id}")
      {:ok, results}
    else
      {:error, reason} ->
        Logger.error("Failed to search similar documents: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get relevant context for RAG (Retrieval-Augmented Generation).
  Returns formatted text context from similar documents.

  ## Parameters
  - user: User struct or user_id
  - query: Search query text
  - opts: Options for similarity search

  ## Returns
  - {:ok, context_text} on success
  - {:error, reason} on failure
  """
  def get_rag_context(user, query, opts \\ %{}) do
    case find_similar_documents(user, query, opts) do
      {:ok, documents} ->
        context =
          documents
          |> Enum.map(fn doc ->
            "#{doc.type |> String.upcase()} from #{doc.source}:\n#{doc.content}\n"
          end)
          |> Enum.join("\n---\n\n")

        {:ok, context}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Delete documents by user and optional filters.

  ## Parameters
  - user: User struct or user_id
  - opts: Options map with optional keys:
    - :types - List of document types to delete
    - :sources - List of sources to delete
    - :older_than - DateTime to delete documents older than

  ## Returns
  - {:ok, deleted_count} on success
  - {:error, reason} on failure
  """
  def delete_documents(user, opts \\ %{}) do
    user_id = get_user_id(user)
    types = Map.get(opts, :types, [])
    sources = Map.get(opts, :sources, [])
    older_than = Map.get(opts, :older_than)

    query = from(d in Document, where: d.user_id == ^user_id)

    # Add filters
    query =
      if Enum.empty?(types) do
        query
      else
        from(d in query, where: d.type in ^types)
      end

    query =
      if Enum.empty?(sources) do
        query
      else
        from(d in query, where: d.source in ^sources)
      end

    query =
      if older_than do
        from(d in query, where: d.inserted_at < ^older_than)
      else
        query
      end

    case Repo.delete_all(query) do
      {count, _} ->
        Logger.info("Deleted #{count} documents for user_id=#{user_id}")
        {:ok, count}

      error ->
        Logger.error("Failed to delete documents: #{inspect(error)}")
        {:error, "Database deletion failed"}
    end
  end

  @doc """
  Get document statistics for a user.

  ## Returns
  - Map with document counts by type and source
  """
  def get_document_stats(user) do
    user_id = get_user_id(user)

    type_stats =
      from(d in Document,
        where: d.user_id == ^user_id,
        group_by: d.type,
        select: {d.type, count(d.id)}
      )
      |> Repo.all()
      |> Map.new()

    source_stats =
      from(d in Document,
        where: d.user_id == ^user_id,
        group_by: d.source,
        select: {d.source, count(d.id)}
      )
      |> Repo.all()
      |> Map.new()

    total_count =
      from(d in Document, where: d.user_id == ^user_id, select: count(d.id))
      |> Repo.one()

    %{
      total: total_count,
      by_type: type_stats,
      by_source: source_stats
    }
  end

  # Private functions

  defp get_user_id(%User{id: id}), do: id
  defp get_user_id(user_id) when is_integer(user_id), do: user_id
  defp get_user_id(_), do: raise("Invalid user parameter")

  defp create_document(user_id, content, source, type, embedding, metadata) do
    attrs = %{
      user_id: user_id,
      content: content,
      source: source,
      type: type,
      embedding: embedding
    }

    case %Document{} |> Document.changeset(attrs) |> Repo.insert() do
      {:ok, document} -> {:ok, document}
      {:error, changeset} -> {:error, "Database insertion failed: #{inspect(changeset.errors)}"}
    end
  end
end
