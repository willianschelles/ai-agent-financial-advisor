defmodule AiAgent.EmbeddingsTest do
  use AiAgent.DataCase, async: true
  
  alias AiAgent.Embeddings
  alias AiAgent.Embeddings.VectorStore
  alias AiAgent.User
  alias AiAgent.Repo

  @moduletag :skip_without_openai

  describe "embeddings" do
    test "embed_text/1 generates embedding vector" do
      # Skip if no OpenAI key
      unless System.get_env("OPENAI_API_KEY") do
        assert {:error, "OpenAI API key not configured"} = Embeddings.embed_text("test")
      else
        assert {:ok, embedding} = Embeddings.embed_text("This is a test document")
        assert is_list(embedding)
        assert length(embedding) == 1536
        assert Enum.all?(embedding, &is_float/1)
      end
    end

    test "embed_text/1 handles empty and invalid input" do
      assert {:error, "Text must be a string"} = Embeddings.embed_text(123)
      assert {:error, "Text must be a string"} = Embeddings.embed_text(nil)
    end

    test "cosine_similarity/2 calculates similarity correctly" do
      vec1 = [1.0, 0.0, 0.0]
      vec2 = [0.0, 1.0, 0.0]
      vec3 = [1.0, 0.0, 0.0]

      assert {:ok, 0.0} = Embeddings.cosine_similarity(vec1, vec2)
      assert {:ok, 1.0} = Embeddings.cosine_similarity(vec1, vec3)
      
      assert {:error, "Vectors must have same dimensions"} = 
        Embeddings.cosine_similarity([1.0], [1.0, 2.0])
    end
  end

  describe "vector store" do
    setup do
      user = Repo.insert!(%User{
        email: "test@example.com",
        google_tokens: %{"access_token" => "test_token"}
      })
      
      %{user: user}
    end

    test "store_document/5 creates document with embedding", %{user: user} do
      # Mock embedding since we may not have OpenAI key in tests
      if System.get_env("OPENAI_API_KEY") do
        assert {:ok, document} = VectorStore.store_document(
          user,
          "This is a test email about baseball",
          "test@client.com",
          "email"
        )
        
        assert document.content == "This is a test email about baseball"
        assert document.source == "test@client.com"
        assert document.type == "email"
        assert document.user_id == user.id
        assert is_list(document.embedding)
      else
        # Test fails gracefully without OpenAI key
        assert {:error, "OpenAI API key not configured"} = VectorStore.store_document(
          user,
          "This is a test email about baseball",
          "test@client.com",
          "email"
        )
      end
    end

    test "get_document_stats/1 returns correct statistics", %{user: user} do
      stats = VectorStore.get_document_stats(user)
      
      assert %{
        total: 0,
        by_type: %{},
        by_source: %{}
      } = stats
    end
  end
end