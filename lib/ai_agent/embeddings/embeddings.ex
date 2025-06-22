defmodule AiAgent.Embeddings do
  @moduledoc """
  Module for generating embeddings using OpenAI's API.
  Handles text vectorization for RAG (Retrieval-Augmented Generation) functionality.
  """

  require Logger

  @openai_embeddings_url "https://api.openai.com/v1/embeddings"
  @embedding_model "text-embedding-3-small"
  @embedding_dimensions 1536
  # OpenAI text-embedding-3-small has a max context of 8192 tokens
  # Roughly 1 token = 4 characters, so we'll limit to ~6000 characters to be safe
  @max_text_length 6000

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

        # Truncate text if it's too long
        cleaned_text = text |> String.trim() |> truncate_text()

        payload = %{
          model: @embedding_model,
          input: cleaned_text,
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
    Logger.info("Embedding batch of #{length(texts)} texts")

    case get_openai_key() do
      nil ->
        Logger.error("OpenAI API key not configured")
        {:error, "OpenAI API key not configured"}

      api_key ->
        headers = [
          {"Authorization", "Bearer #{api_key}"},
          {"Content-Type", "application/json"}
        ]

        # Clean, validate, and truncate texts
        cleaned_texts =
          texts
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&(String.length(&1) > 0))
          |> Enum.map(&truncate_text/1)

        Logger.debug("Cleaned texts count: #{length(cleaned_texts)}")

        if Enum.empty?(cleaned_texts) do
          Logger.warn("No valid texts provided for embedding")
          {:error, "No valid texts provided"}
        else
          payload = %{
            model: @embedding_model,
            input: cleaned_texts,
            dimensions: @embedding_dimensions
          }

          Logger.debug("Sending batch embedding request to OpenAI")

          start_time = System.monotonic_time()

          result =
            case Req.post(@openai_embeddings_url, headers: headers, json: payload) do
              {:ok, %{status: 200, body: %{"data" => embeddings}}} ->
                vectors = Enum.map(embeddings, & &1["embedding"])
                Logger.info("Received #{length(vectors)} embeddings from OpenAI")
                {:ok, vectors}

              {:ok, %{status: status, body: body}} ->
                Logger.error("OpenAI API error: status=#{status}, body=#{inspect(body)}")
                {:error, "OpenAI API error: #{status}"}

              {:error, reason} ->
                Logger.error("Failed to call OpenAI API: #{inspect(reason)}")
                {:error, "Network error: #{inspect(reason)}"}
            end

          elapsed_ms =
            System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)

          Logger.info("Embedding batch request took #{elapsed_ms} ms")
          result
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

  @doc """
  Truncate text to stay within OpenAI's token limits.
  Also provides a summary when text is truncated.
  """
  def truncate_text(text) when is_binary(text) do
    if String.length(text) <= @max_text_length do
      text
    else
      # Truncate and add indication
      truncated = String.slice(text, 0, @max_text_length - 100)

      # Try to cut at a word boundary
      truncated =
        case String.split(truncated, " ") do
          words when length(words) > 1 ->
            words |> Enum.drop(-1) |> Enum.join(" ")

          _ ->
            truncated
        end

      Logger.warning(
        "Text truncated from #{String.length(text)} to #{String.length(truncated)} characters"
      )

      truncated <> "... [TEXT TRUNCATED - Original length: #{String.length(text)} chars]"
    end
  end

  def truncate_text(_), do: ""
end
