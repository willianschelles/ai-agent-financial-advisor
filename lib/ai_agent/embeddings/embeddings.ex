defmodule AiAgent.Embeddings do
  @moduledoc """
  Module for generating embeddings using OpenAI's API.
  Handles text vectorization for RAG (Retrieval-Augmented Generation) functionality.
  """

  require Logger

  @openai_embeddings_url "https://api.openai.com/v1/embeddings"
  @embedding_model "text-embedding-3-small"
  @embedding_dimensions 1536

  @doc """
  Generate embedding vector for given text using OpenAI's embedding API.

  ## Parameters
  - text: String content to be embedded

  ## Returns
  - {:ok, vector} on success
  - {:error, reason} on failure
  """
  def embed_text(text) when is_binary(text) do
    case get_openai_key() do
      nil ->
        {:error, "OpenAI API key not configured"}

      api_key ->
        headers = [
          {"Authorization", "Bearer #{api_key}"},
          {"Content-Type", "application/json"}
        ]

        payload = %{
          model: @embedding_model,
          input: String.trim(text),
          dimensions: @embedding_dimensions
        }

        case Req.post(@openai_embeddings_url, headers: headers, json: payload) do
          {:ok, %{status: 200, body: %{"data" => [%{"embedding" => embedding}]}}} ->
            {:ok, embedding}

          {:ok, %{status: status, body: body}} ->
            Logger.error("OpenAI API error: status=#{status}, body=#{inspect(body)}")
            {:error, "OpenAI API error: #{status}"}

          {:error, reason} ->
            Logger.error("Failed to call OpenAI API: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end
    end
  end

  def embed_text(_), do: {:error, "Text must be a string"}

  @doc """
  Batch embed multiple texts. More efficient than individual calls.

  ## Parameters
  - texts: List of strings to be embedded

  ## Returns
  - {:ok, [vectors]} on success
  - {:error, reason} on failure
  """
  def embed_texts(texts) when is_list(texts) do
    case get_openai_key() do
      nil ->
        {:error, "OpenAI API key not configured"}

      api_key ->
        headers = [
          {"Authorization", "Bearer #{api_key}"},
          {"Content-Type", "application/json"}
        ]

        # Clean and validate texts
        cleaned_texts =
          texts
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&(String.length(&1) > 0))

        if Enum.empty?(cleaned_texts) do
          {:error, "No valid texts provided"}
        else
          payload = %{
            model: @embedding_model,
            input: cleaned_texts,
            dimensions: @embedding_dimensions
          }

          case Req.post(@openai_embeddings_url, headers: headers, json: payload) do
            {:ok, %{status: 200, body: %{"data" => embeddings}}} ->
              vectors = Enum.map(embeddings, & &1["embedding"])
              {:ok, vectors}

            {:ok, %{status: status, body: body}} ->
              Logger.error("OpenAI API error: status=#{status}, body=#{inspect(body)}")
              {:error, "OpenAI API error: #{status}"}

            {:error, reason} ->
              Logger.error("Failed to call OpenAI API: #{inspect(reason)}")
              {:error, "Network error: #{inspect(reason)}"}
          end
        end
    end
  end

  def embed_texts(_), do: {:error, "Texts must be a list"}

  @doc """
  Calculate cosine similarity between two embedding vectors.
  Used for finding similar documents in RAG queries.
  """
  def cosine_similarity(vec1, vec2) when is_list(vec1) and is_list(vec2) do
    if length(vec1) != length(vec2) do
      {:error, "Vectors must have same dimensions"}
    else
      dot_product =
        vec1
        |> Enum.zip(vec2)
        |> Enum.map(fn {a, b} -> a * b end)
        |> Enum.sum()

      magnitude1 = :math.sqrt(Enum.sum(Enum.map(vec1, &(&1 * &1))))
      magnitude2 = :math.sqrt(Enum.sum(Enum.map(vec2, &(&1 * &1))))

      if magnitude1 == 0 or magnitude2 == 0 do
        {:ok, 0.0}
      else
        similarity = dot_product / (magnitude1 * magnitude2)
        {:ok, similarity}
      end
    end
  end

  def cosine_similarity(_, _), do: {:error, "Both arguments must be lists"}

  # Private functions

  defp get_openai_key do
    System.get_env("OPENAI_API_KEY")
  end
end
