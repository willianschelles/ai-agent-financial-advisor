defmodule AiAgent.Embeddings.FixTest do
  @moduledoc """
  Test functions to verify the OpenAI token limit and PostgreSQL vector fixes.
  """

  alias AiAgent.Embeddings
  alias AiAgent.Embeddings.VectorStore
  alias AiAgent.User
  alias AiAgent.Repo

  @doc """
  Test the OpenAI token limit fix with a very long text.

  ## Usage in IEx:
  iex> AiAgent.Embeddings.FixTest.test_long_text_embedding()
  """
  def test_long_text_embedding do
    IO.puts("🧪 Testing OpenAI token limit fix...")

    # Create a very long text (longer than 8192 tokens)
    long_text =
      """
      This is a very long email that would normally cause the OpenAI API to fail.
      """
      # This creates a ~25,000 character text
      |> String.duplicate(500)

    IO.puts("📏 Original text length: #{String.length(long_text)} characters")

    case Embeddings.embed_text(long_text) do
      {:ok, embedding} ->
        IO.puts("✅ Successfully generated embedding for long text!")
        IO.puts("📊 Embedding dimensions: #{length(embedding)}")
        {:ok, embedding}

      {:error, reason} ->
        IO.puts("❌ Failed to generate embedding: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Test the PostgreSQL vector storage fix.

  ## Usage in IEx:
  iex> AiAgent.Embeddings.FixTest.test_vector_storage()
  """
  def test_vector_storage do
    IO.puts("🧪 Testing PostgreSQL vector storage fix...")

    # Get or create test user
    user = get_or_create_test_user()

    # Test with a moderate length text
    test_content =
      "This is a test document for vector storage. It contains information about testing embeddings."

    case VectorStore.store_document(user, test_content, "test@example.com", "test_email") do
      {:ok, document} ->
        IO.puts("✅ Successfully stored document with vector embedding!")
        IO.puts("📄 Document ID: #{document.id}")
        IO.puts("📊 Embedding stored: #{is_list(document.embedding)}")
        IO.puts("📏 Embedding dimensions: #{length(document.embedding || [])}")

        # Test retrieval
        test_search(user)

        {:ok, document}

      {:error, reason} ->
        IO.puts("❌ Failed to store document: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Test both fixes together with batch processing.
  """
  def test_both_fixes do
    IO.puts("🧪 Testing both fixes together...")

    user = get_or_create_test_user()

    # Create test documents with varying lengths
    test_docs = [
      %{
        content: "Short email about a meeting.",
        source: "client1@example.com",
        type: "email"
      },
      %{
        content: String.duplicate("This is a medium length email with more content. ", 50),
        source: "client2@example.com",
        type: "email"
      },
      %{
        content:
          String.duplicate(
            "This is a very long email that would normally cause issues with token limits. ",
            200
          ),
        source: "client3@example.com",
        type: "email"
      }
    ]

    IO.puts("📊 Testing #{length(test_docs)} documents")

    case VectorStore.store_documents_batch(user, test_docs) do
      {:ok, documents} ->
        IO.puts("✅ Successfully stored #{length(documents)} documents!")

        # Test search functionality
        IO.puts("\n🔍 Testing search functionality...")
        test_search(user)

        {:ok, documents}

      {:error, reason} ->
        IO.puts("❌ Batch storage failed: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Run all tests in sequence.
  """
  def run_all_tests do
    IO.puts("🚀 Running all embedding fix tests...\n")

    results = %{
      token_limit: test_long_text_embedding(),
      vector_storage: test_vector_storage(),
      batch_processing: test_both_fixes()
    }

    IO.puts("\n📋 Test Summary:")

    Enum.each(results, fn {test, result} ->
      status =
        case result do
          {:ok, _} -> "✅ PASSED"
          {:error, _} -> "❌ FAILED"
        end

      IO.puts("  #{test}: #{status}")
    end)

    # Check if all passed
    all_passed = Enum.all?(results, fn {_, result} -> match?({:ok, _}, result) end)

    if all_passed do
      IO.puts("\n🎉 All tests passed! The fixes are working correctly.")
    else
      IO.puts("\n⚠️  Some tests failed. Check the output above for details.")
    end

    results
  end

  # Private helper functions

  defp get_or_create_test_user do
    case Repo.get_by(User, email: "fixtest@example.com") do
      nil ->
        Repo.insert!(%User{
          email: "fixtest@example.com",
          google_tokens: %{"access_token" => "test_token"}
        })

      user ->
        user
    end
  end

  defp test_search(user) do
    case VectorStore.find_similar_documents(user, "test meeting", %{limit: 3, threshold: 0.1}) do
      {:ok, results} ->
        IO.puts("🔍 Search found #{length(results)} similar documents")

        Enum.each(results, fn doc ->
          IO.puts(
            "  - #{doc.type} from #{doc.source} (similarity: #{Float.round(doc.similarity, 3)})"
          )
        end)

      {:error, reason} ->
        IO.puts("🔍 Search failed: #{reason}")
    end
  end
end
