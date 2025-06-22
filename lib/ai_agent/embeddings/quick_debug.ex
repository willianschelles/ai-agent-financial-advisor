defmodule AiAgent.Embeddings.QuickDebug do
  @moduledoc """
  Quick debugging functions for similarity issues.
  """

  alias AiAgent.Embeddings.SimilarityDebug
  alias AiAgent.LLM.RAGQuery
  alias AiAgent.User
  alias AiAgent.Repo

  @doc """
  One-command debug for the "Avenue" issue.

  ## Usage:
  iex> AiAgent.Embeddings.QuickDebug.debug_avenue_issue()
  """
  def debug_avenue_issue do
    IO.puts("🔍 === DEBUGGING 'AVENUE' ISSUE ===")

    # Find the user
    case Repo.all(User) do
      [] ->
        IO.puts("❌ No users found in database")
        {:error, "No users"}

      users ->
        # Use first user
        user = hd(users)
        IO.puts("👤 Using user: #{user.email} (ID: #{user.id})")

        # Debug the specific query
        debug_query(user, "Avenue")
    end
  end

  @doc """
  Debug a specific query for a specific user.
  """
  def debug_query(user, query) do
    IO.puts("\n🔍 Debugging query: '#{query}'")

    # 1. Show all similarity scores
    IO.puts("\n=== STEP 1: ALL SIMILARITY SCORES ===")
    SimilarityDebug.debug_similarity_scores(user, query)

    # 2. Test different thresholds
    IO.puts("\n=== STEP 2: THRESHOLD TESTING ===")
    SimilarityDebug.test_thresholds(user, query)

    # 3. Test RAG with lower threshold
    IO.puts("\n=== STEP 3: RAG WITH LOWER THRESHOLD ===")
    test_rag_with_threshold(user, query, 0.1)

    # 4. Test RAG with the new default
    IO.puts("\n=== STEP 4: RAG WITH NEW DEFAULT (0.3) ===")
    test_rag_with_threshold(user, query, 0.3)
  end

  @doc """
  Test RAG with a specific threshold.
  """
  def test_rag_with_threshold(user, query, threshold) do
    IO.puts("🧪 Testing RAG with threshold: #{threshold}")

    opts = %{similarity_threshold: threshold}

    case RAGQuery.ask(user, query, opts) do
      {:ok, result} ->
        IO.puts("✅ Success! Found #{length(result.context_used)} documents")
        IO.puts("📄 Response: #{String.slice(result.response, 0, 200)}...")

        if length(result.context_used) > 0 do
          IO.puts("\n📋 Context documents:")

          Enum.each(result.context_used, fn doc ->
            IO.puts("  • #{doc.source} (similarity: #{Float.round(doc.similarity, 3)})")
            IO.puts("    #{String.slice(doc.content, 0, 100)}...")
          end)
        end

      {:error, reason} ->
        IO.puts("❌ Failed: #{reason}")
    end
  end

  @doc """
  Show all documents for a user (helpful for debugging).
  """
  def show_all_user_documents(user_email) do
    case Repo.get_by(User, email: user_email) do
      nil ->
        IO.puts("❌ User not found: #{user_email}")

      user ->
        import Ecto.Query
        alias AiAgent.Document

        documents =
          from(d in Document,
            where: d.user_id == ^user.id,
            select: %{
              id: d.id,
              type: d.type,
              source: d.source,
              content: fragment("LEFT(?, 200)", d.content)
            }
          )
          |> Repo.all()

        IO.puts("📚 All documents for #{user.email}:")
        IO.puts("Total: #{length(documents)} documents")
        IO.puts("")

        Enum.with_index(documents, 1)
        |> Enum.each(fn {doc, index} ->
          IO.puts("#{index}. [#{doc.type}] #{doc.source}")
          IO.puts("   #{doc.content}...")
          IO.puts("")
        end)
    end
  end

  @doc """
  Quick test - just try to search for "Avenue" with very low threshold.
  """
  def quick_avenue_test do
    case Repo.all(User) do
      [user | _] ->
        IO.puts("🚀 Quick Avenue Test with user: #{user.email}")

        # Test with very low threshold
        alias AiAgent.Embeddings.VectorStore

        case VectorStore.find_similar_documents(user, "Avenue", %{threshold: 0.0, limit: 10}) do
          {:ok, results} ->
            IO.puts("✅ Found #{length(results)} documents with threshold 0.0:")

            Enum.take(results, 5)
            |> Enum.each(fn doc ->
              similarity = Float.round(doc.similarity, 4)
              contains_avenue = String.contains?(String.downcase(doc.content), "avenue")
              marker = if contains_avenue, do: "🎯", else: "  "

              IO.puts("#{marker} [#{similarity}] #{doc.source}")
              IO.puts("     #{String.slice(doc.content, 0, 80)}...")
            end)

          {:error, reason} ->
            IO.puts("❌ Error: #{reason}")
        end

      [] ->
        IO.puts("❌ No users found")
    end
  end
end
