defmodule AiAgent.Embeddings.Demo do
  @moduledoc """
  Demo module for testing embeddings and RAG functionality.
  Run these examples in IEx to verify the implementation works.
  """

  alias AiAgent.Embeddings
  alias AiAgent.Embeddings.VectorStore
  alias AiAgent.Embeddings.RAG
  alias AiAgent.User
  alias AiAgent.Repo

  @doc """
  Run a simple embedding demo.
  
  ## Usage in IEx:
  iex> AiAgent.Embeddings.Demo.test_embeddings()
  """
  def test_embeddings do
    IO.puts("Testing OpenAI embeddings...")
    
    case Embeddings.embed_text("This is a test document about financial planning") do
      {:ok, embedding} ->
        IO.puts("✓ Successfully generated embedding")
        IO.puts("  Vector length: #{length(embedding)}")
        IO.puts("  First few values: #{Enum.take(embedding, 3) |> inspect}")
        {:ok, embedding}
      
      {:error, reason} ->
        IO.puts("✗ Failed to generate embedding: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Test vector storage with sample data.
  
  ## Usage in IEx:
  iex> AiAgent.Embeddings.Demo.test_vector_store()
  """
  def test_vector_store do
    IO.puts("Testing vector store with sample data...")
    
    # Create or find test user
    user = get_or_create_test_user()
    
    # Sample documents
    sample_docs = [
      %{
        content: "My kid plays baseball every Saturday. We usually go to the games together.",
        source: "client_a@example.com",
        type: "email"
      },
      %{
        content: "I'm thinking about selling my AAPL shares. The stock has been performing well.",
        source: "client_b@example.com", 
        type: "email"
      },
      %{
        content: "John Smith works at Tech Corp. He's interested in retirement planning.",
        source: "hubspot_contact",
        type: "hubspot_contact"
      }
    ]
    
    case VectorStore.store_documents_batch(user, sample_docs) do
      {:ok, documents} ->
        IO.puts("✓ Successfully stored #{length(documents)} documents")
        
        # Test similarity search
        test_search(user)
        
        {:ok, documents}
      
      {:error, reason} ->
        IO.puts("✗ Failed to store documents: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Test RAG context retrieval.
  
  ## Usage in IEx:
  iex> AiAgent.Embeddings.Demo.test_rag()
  """
  def test_rag do
    IO.puts("Testing RAG context retrieval...")
    
    user = get_or_create_test_user()
    
    # Ensure we have some test data
    test_vector_store()
    
    queries = [
      "Who mentioned their kid plays baseball?",
      "Why did someone want to sell AAPL stock?",
      "Tell me about John Smith"
    ]
    
    Enum.each(queries, fn query ->
      IO.puts("\n--- Query: #{query} ---")
      
      case RAG.answer_question(user, query) do
        {:ok, context} ->
          IO.puts("✓ Found relevant context:")
          IO.puts(String.slice(context, 0, 300) <> "...")
        
        {:error, reason} ->
          IO.puts("✗ Failed to get context: #{reason}")
      end
    end)
  end

  @doc """
  Run all demos in sequence.
  
  ## Usage in IEx:
  iex> AiAgent.Embeddings.Demo.run_all()
  """
  def run_all do
    IO.puts("Running complete embeddings and RAG demo...\n")
    
    with {:ok, _} <- test_embeddings(),
         {:ok, _} <- test_vector_store() do
      test_rag()
      IO.puts("\n✓ All demos completed successfully!")
    else
      {:error, reason} ->
        IO.puts("\n✗ Demo failed: #{reason}")
    end
  end

  # Private helper functions

  defp get_or_create_test_user do
    case Repo.get_by(User, email: "demo@example.com") do
      nil ->
        Repo.insert!(%User{
          email: "demo@example.com",
          google_tokens: %{"access_token" => "demo_token"}
        })
      
      user ->
        user
    end
  end

  defp test_search(user) do
    IO.puts("\nTesting similarity search...")
    
    queries = [
      "baseball",
      "AAPL stock",
      "retirement planning"
    ]
    
    Enum.each(queries, fn query ->
      case VectorStore.find_similar_documents(user, query, %{limit: 2, threshold: 0.5}) do
        {:ok, results} ->
          IO.puts("  Query '#{query}': found #{length(results)} results")
          Enum.each(results, fn doc ->
            IO.puts("    - #{doc.type} from #{doc.source} (similarity: #{Float.round(doc.similarity, 3)})")
          end)
        
        {:error, reason} ->
          IO.puts("  Query '#{query}' failed: #{reason}")
      end
    end)
  end
end