defmodule AiAgent.Embeddings.SimilarityDebug do
  @moduledoc """
  Debug functions for similarity search issues.
  Helps identify why certain queries don't return expected results.
  """

  import Ecto.Query
  require Logger

  alias AiAgent.Repo
  alias AiAgent.Document
  alias AiAgent.User
  alias AiAgent.Embeddings

  @doc """
  Debug similarity scores for a specific query without any threshold filtering.
  Shows all documents and their similarity scores to help determine appropriate thresholds.

  ## Usage:
  iex> user = AiAgent.Repo.get_by(AiAgent.User, email: "your-email@example.com")
  iex> AiAgent.Embeddings.SimilarityDebug.debug_similarity_scores(user, "Avenue")
  """
  def debug_similarity_scores(user, query_text) do
    IO.puts("=== SIMILARITY DEBUG ===")
    IO.puts("User: #{user.email} (ID: #{user.id})")
    IO.puts("Query: \"#{query_text}\"")
    IO.puts("")

    user_id = get_user_id(user)

    # First, check if user has any documents
    doc_count =
      from(d in Document, where: d.user_id == ^user_id, select: count(d.id)) |> Repo.one()

    if doc_count == 0 do
      IO.puts("User has no documents stored.")
      {:error, "No documents"}
    end

    IO.puts("User has #{doc_count} documents total")

    # Generate embedding for the query
    case Embeddings.embed_text(query_text) do
      {:ok, query_embedding} ->
        IO.puts("Query embedding generated successfully")

        # Get ALL documents with their similarity scores (no threshold)
        query =
          from(d in Document,
            where: d.user_id == ^user_id,
            select: %{
              id: d.id,
              # First 100 chars
              content: fragment("LEFT(?, 100)", d.content),
              full_content: d.content,
              source: d.source,
              type: d.type,
              similarity: fragment("1 - (? <=> ?)", d.embedding, ^query_embedding)
            },
            order_by: [desc: fragment("1 - (? <=> ?)", d.embedding, ^query_embedding)]
          )

        results = Repo.all(query)

        IO.puts("\nALL DOCUMENTS WITH SIMILARITY SCORES:")
        IO.puts("Format: [Similarity] Source (Type) - Content preview")
        IO.puts(String.duplicate("=", 80))

        Enum.with_index(results, 1)
        |> Enum.each(fn {doc, index} ->
          similarity = Float.round(doc.similarity, 4)
          content_preview = String.slice(doc.content, 0, 60) <> "..."

          # Text label based on similarity
          label =
            cond do
              similarity >= 0.8 -> "[HIGH]"
              similarity >= 0.6 -> "[MEDIUM]"
              similarity >= 0.4 -> "[LOW]"
              true -> "[VERY LOW]"
            end

          IO.puts("#{index}. #{label} [#{similarity}] #{doc.source} (#{doc.type})")
          IO.puts("    #{content_preview}")

          # Check if this document contains the search term
          if String.contains?(String.downcase(doc.full_content), String.downcase(query_text)) do
            IO.puts("    CONTAINS SEARCH TERM!")
          end

          IO.puts("")
        end)

        # Show threshold analysis
        show_threshold_analysis(results)

        # Show specific document analysis if search term is found
        matching_docs =
          Enum.filter(results, fn doc ->
            String.contains?(String.downcase(doc.full_content), String.downcase(query_text))
          end)

        if length(matching_docs) > 0 do
          IO.puts("\nDOCUMENTS CONTAINING '#{query_text}':")

          Enum.each(matching_docs, fn doc ->
            IO.puts("  • Similarity: #{Float.round(doc.similarity, 4)} - #{doc.source}")
            IO.puts("    Content: #{String.slice(doc.full_content, 0, 150)}...")
          end)
        else
          IO.puts("\nNo documents contain the exact term '#{query_text}'")
          suggest_related_terms(results, query_text)
        end

        {:ok, results}

      {:error, reason} ->
        IO.puts("Failed to generate query embedding: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Test different similarity thresholds to see how many results you get.
  """
  def test_thresholds(
        user,
        query_text,
        thresholds \\ [0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1]
      ) do
    IO.puts("THRESHOLD TESTING")
    IO.puts("Query: \"#{query_text}\"")
    IO.puts("")

    case debug_similarity_scores(user, query_text) do
      {:ok, all_results} ->
        IO.puts("\nRESULTS BY THRESHOLD:")
        IO.puts("Threshold | Count | Top Similarity")
        IO.puts(String.duplicate("-", 35))

        Enum.each(thresholds, fn threshold ->
          matching = Enum.filter(all_results, &(&1.similarity >= threshold))
          count = length(matching)
          top_sim = if count > 0, do: Float.round(hd(matching).similarity, 3), else: "N/A"

          status =
            cond do
              count == 0 -> "[NONE]"
              count <= 3 -> "[FEW]"
              count <= 10 -> "[OK]"
              true -> "[MANY]"
            end

          IO.puts(
            "#{status} #{threshold}      | #{String.pad_leading("#{count}", 4)} | #{top_sim}"
          )
        end)

        # Recommend optimal threshold
        recommend_threshold(all_results)

      {:error, reason} ->
        IO.puts("Failed to test thresholds: #{reason}")
    end
  end

  @doc """
  Quick fix function - finds the best threshold for a specific query.
  """
  def suggest_threshold(user, query_text) do
    case debug_similarity_scores(user, query_text) do
      {:ok, results} ->
        if length(results) > 0 do
          max_similarity = hd(results).similarity
          # 0.2 below max, minimum 0.1
          suggested_threshold = max(0.1, max_similarity - 0.2)

          IO.puts("\nSUGGESTED THRESHOLD: #{Float.round(suggested_threshold, 2)}")
          IO.puts("   (Max similarity: #{Float.round(max_similarity, 3)})")

          # Test the suggested threshold
          matching = Enum.filter(results, &(&1.similarity >= suggested_threshold))
          IO.puts("   Would return #{length(matching)} documents")

          suggested_threshold
        else
          IO.puts("No documents found")
          nil
        end

      {:error, _} ->
        nil
    end
  end

  # Private helper functions

  defp get_user_id(%User{id: id}), do: id
  defp get_user_id(user_id) when is_integer(user_id), do: user_id
  defp get_user_id(_), do: raise("Invalid user parameter")

  defp show_threshold_analysis(results) do
    if length(results) > 0 do
      max_sim = hd(results).similarity
      min_sim = List.last(results).similarity

      IO.puts("SIMILARITY RANGE:")
      IO.puts("   Highest: #{Float.round(max_sim, 4)}")
      IO.puts("   Lowest:  #{Float.round(min_sim, 4)}")
      IO.puts("   Spread:  #{Float.round(max_sim - min_sim, 4)}")

      # Count by ranges
      high = Enum.count(results, &(&1.similarity >= 0.8))
      medium = Enum.count(results, &(&1.similarity >= 0.6 and &1.similarity < 0.8))
      low = Enum.count(results, &(&1.similarity >= 0.4 and &1.similarity < 0.6))
      very_low = Enum.count(results, &(&1.similarity < 0.4))

      IO.puts("\nDISTRIBUTION:")
      IO.puts("   High (≥0.8):     #{high} documents")
      IO.puts("   Medium (0.6-0.8): #{medium} documents")
      IO.puts("   Low (0.4-0.6):    #{low} documents")
      IO.puts("   Very Low (<0.4):  #{very_low} documents")
    end
  end

  defp recommend_threshold(results) do
    if length(results) > 0 do
      max_sim = hd(results).similarity

      recommended =
        cond do
          max_sim >= 0.8 -> 0.6
          max_sim >= 0.6 -> 0.4
          max_sim >= 0.4 -> 0.2
          true -> 0.1
        end

      IO.puts("\nRECOMMENDED THRESHOLD: #{recommended}")
      IO.puts("   Reason: Max similarity is #{Float.round(max_sim, 3)}")

      matching_count = Enum.count(results, &(&1.similarity >= recommended))
      IO.puts("   Would return: #{matching_count} documents")
    end
  end

  defp suggest_related_terms(results, query_text) do
    IO.puts("\nLOOKING FOR RELATED TERMS...")

    # Look for partial matches in content
    partial_matches =
      Enum.filter(results, fn doc ->
        content_lower = String.downcase(doc.full_content)
        query_lower = String.downcase(query_text)

        # Check if any words in the query appear in the content
        query_words = String.split(query_lower, ~r/\W+/, trim: true)
        Enum.any?(query_words, fn word -> String.contains?(content_lower, word) end)
      end)

    if length(partial_matches) > 0 do
      IO.puts("Found #{length(partial_matches)} documents with partial matches:")

      Enum.take(partial_matches, 3)
      |> Enum.each(fn doc ->
        IO.puts("  - #{doc.source}: #{String.slice(doc.full_content, 0, 100)}...")
      end)
    else
      IO.puts("No partial matches found either.")
    end
  end
end
