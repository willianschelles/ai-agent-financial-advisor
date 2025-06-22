defmodule AiAgent.LLM.RAGDemo do
  @moduledoc """
  Demo and testing functions for the complete RAG system.
  Shows how to use the RAG query functionality with real examples.
  """

  alias AiAgent.LLM.RAGQuery
  alias AiAgent.Embeddings.VectorStore
  alias AiAgent.User
  alias AiAgent.Repo

  @doc """
  Complete RAG demonstration with sample data.
  
  ## Usage in IEx:
  iex> AiAgent.LLM.RAGDemo.run_complete_demo()
  """
  def run_complete_demo do
    IO.puts("🚀 === COMPLETE RAG SYSTEM DEMO ===")
    IO.puts("This demo shows the full RAG pipeline:")
    IO.puts("1. Document storage with embeddings")
    IO.puts("2. Question embedding and similarity search")
    IO.puts("3. LLM response generation with context")
    IO.puts("")
    
    # Step 1: Setup test user and data
    IO.puts("📊 Step 1: Setting up test data...")
    user = setup_demo_user()
    setup_demo_documents(user)
    
    # Step 2: Run various RAG queries
    IO.puts("\n🔍 Step 2: Running RAG queries...")
    run_demo_queries(user)
    
    # Step 3: Show context retrieval
    IO.puts("\n📋 Step 3: Showing context retrieval...")
    show_context_examples(user)
    
    IO.puts("\n✅ Demo completed! The RAG system is working correctly.")
  end

  @doc """
  Test the RAG system with a specific question.
  
  ## Usage:
  iex> user = AiAgent.Repo.get_by(AiAgent.User, email: "your-email")
  iex> AiAgent.LLM.RAGDemo.test_question(user, "Who mentioned baseball?")
  """
  def test_question(user, question) do
    IO.puts("🤔 Testing RAG with question: \"#{question}\"")
    IO.puts("")
    
    case RAGQuery.ask(user, question) do
      {:ok, result} ->
        IO.puts("✅ RAG Response:")
        IO.puts("#{result.response}")
        IO.puts("")
        IO.puts("📊 Context Used:")
        
        Enum.each(result.context_used, fn doc ->
          IO.puts("  • #{doc.type} from #{doc.source} (similarity: #{Float.round(doc.similarity, 3)})")
          IO.puts("    \"#{String.slice(doc.content, 0, 100)}...\"")
        end)
        
        IO.puts("")
        IO.puts("🔧 Metadata:")
        IO.inspect(result.metadata, pretty: true)
        
        result
      
      {:error, reason} ->
        IO.puts("❌ RAG Query failed: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Compare RAG vs non-RAG responses to show the difference.
  """
  def compare_with_and_without_rag(user, question) do
    IO.puts("🆚 Comparing responses WITH and WITHOUT RAG for:")
    IO.puts("   \"#{question}\"")
    IO.puts("")
    
    # Response WITH RAG
    IO.puts("📚 WITH RAG CONTEXT:")
    case RAGQuery.ask(user, question) do
      {:ok, result} ->
        IO.puts("#{result.response}")
        IO.puts("\n📄 (Used #{length(result.context_used)} documents as context)")
      {:error, reason} ->
        IO.puts("Error: #{reason}")
    end
    
    IO.puts("\n" <> String.duplicate("=", 50))
    
    # Response WITHOUT RAG (just direct LLM call)
    IO.puts("🚫 WITHOUT RAG CONTEXT:")
    case call_llm_directly(question) do
      {:ok, response} ->
        IO.puts("#{response}")
        IO.puts("\n📄 (No context provided)")
      {:error, reason} ->
        IO.puts("Error: #{reason}")
    end
    
    IO.puts("\n💡 Notice how RAG provides specific, contextual answers!")
  end

  @doc """
  Show what documents would be retrieved for different questions.
  """
  def show_context_retrieval(user, questions) when is_list(questions) do
    IO.puts("🔍 Context Retrieval Analysis")
    IO.puts("Showing which documents would be retrieved for different questions:")
    IO.puts("")
    
    Enum.each(questions, fn question ->
      IO.puts("❓ Question: \"#{question}\"")
      
      case RAGQuery.get_context_only(user, question) do
        {:ok, %{documents: docs}} ->
          if Enum.empty?(docs) do
            IO.puts("   📭 No relevant documents found")
          else
            IO.puts("   📄 Found #{length(docs)} relevant documents:")
            
            Enum.each(docs, fn doc ->
              IO.puts("     • #{doc.type} from #{doc.source} (similarity: #{Float.round(doc.similarity, 3)})")
              IO.puts("       \"#{String.slice(doc.content, 0, 80)}...\"")
            end)
          end
        
        {:error, reason} ->
          IO.puts("   ❌ Error: #{reason}")
      end
      
      IO.puts("")
    end)
  end

  @doc """
  Benchmark the RAG system performance.
  """
  def benchmark_rag_performance(user, test_questions \\ nil) do
    questions = test_questions || [
      "Who mentioned their kid plays baseball?",
      "What did someone say about AAPL stock?",
      "Who works at Tech Corp?",
      "What meetings are scheduled?",
      "Who sent an email about retirement planning?"
    ]
    
    IO.puts("⏱️  RAG Performance Benchmark")
    IO.puts("Testing #{length(questions)} questions...")
    IO.puts("")
    
    results = Enum.map(questions, fn question ->
      start_time = System.monotonic_time(:millisecond)
      
      result = case RAGQuery.ask(user, question) do
        {:ok, response} ->
          {
            :success,
            String.length(response.response),
            length(response.context_used)
          }
        {:error, _} ->
          {:error, 0, 0}
      end
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      {question, result, duration}
    end)
    
    # Display results
    total_time = Enum.sum(Enum.map(results, fn {_, _, duration} -> duration end))
    successful = Enum.count(results, fn {_, {status, _, _}, _} -> status == :success end)
    
    IO.puts("📊 Results:")
    IO.puts("  Total questions: #{length(questions)}")
    IO.puts("  Successful: #{successful}")
    IO.puts("  Total time: #{total_time}ms")
    IO.puts("  Average time per question: #{round(total_time / length(questions))}ms")
    IO.puts("")
    
    IO.puts("📋 Individual Results:")
    Enum.each(results, fn {question, {status, response_length, docs_used}, duration} ->
      status_icon = if status == :success, do: "✅", else: "❌"
      IO.puts("  #{status_icon} #{duration}ms | #{docs_used} docs | #{response_length} chars | #{String.slice(question, 0, 40)}...")
    end)
    
    results
  end

  # Private helper functions

  defp setup_demo_user do
    email = "rag_demo@example.com"
    
    case Repo.get_by(User, email: email) do
      nil ->
        user = Repo.insert!(%User{
          email: email,
          google_tokens: %{"access_token" => "demo_token"},
          hubspot_tokens: %{"access_token" => "demo_hubspot_token"}
        })
        IO.puts("✅ Created demo user: #{email}")
        user
      
      user ->
        IO.puts("✅ Using existing demo user: #{email}")
        user
    end
  end

  defp setup_demo_documents(user) do
    # Clear existing demo documents
    VectorStore.delete_documents(user, %{})
    
    demo_docs = [
      %{
        content: "Hey! Just wanted to let you know that my kid Tommy plays baseball every Saturday at the local park. We're really excited about the season. He's on the Tigers team this year!",
        source: "john.smith@gmail.com",
        type: "email"
      },
      %{
        content: "I've been thinking about selling my AAPL shares. The stock has been performing really well lately, up about 15% this quarter. What do you think about the timing?",
        source: "sarah.johnson@gmail.com", 
        type: "email"
      },
      %{
        content: "Contact: Mike Wilson\nEmail: mike.wilson@techcorp.com\nCompany: Tech Corp\nPosition: CTO\nNotes: Interested in retirement planning options for executives.",
        source: "hubspot_contact",
        type: "hubspot_contact"
      },
      %{
        content: "Meeting scheduled for next Tuesday at 2 PM with the Johnson family to discuss their college savings plan. They have twin daughters starting high school.",
        source: "calendar_event",
        type: "calendar"
      },
      %{
        content: "Looking into 401k rollover options. My company was acquired and I need to move my retirement funds. Can we set up a meeting to discuss the best approach?",
        source: "david.chen@outlook.com",
        type: "email"
      },
      %{
        content: "Thanks for the great advice on diversifying my portfolio. I've decided to go with the balanced approach we discussed. My wife is also interested in meeting with you.",
        source: "lisa.martinez@yahoo.com",
        type: "email"
      }
    ]
    
    case VectorStore.store_documents_batch(user, demo_docs) do
      {:ok, documents} ->
        IO.puts("✅ Stored #{length(documents)} demo documents with embeddings")
      {:error, reason} ->
        IO.puts("❌ Failed to store demo documents: #{reason}")
    end
  end

  defp run_demo_queries(user) do
    demo_questions = [
      "Who mentioned their kid plays baseball?",
      "What did someone say about AAPL stock?", 
      "Who works at Tech Corp?",
      "What meetings do I have scheduled?",
      "Who asked about retirement planning?"
    ]
    
    Enum.each(demo_questions, fn question ->
      IO.puts("🤔 Question: \"#{question}\"")
      
      case RAGQuery.quick_ask(user, question) do
        response when is_binary(response) ->
          IO.puts("🤖 Answer: #{response}")
        error ->
          IO.puts("❌ Error: #{error}")
      end
      
      IO.puts("")
    end)
  end

  defp show_context_examples(user) do
    example_questions = [
      "Tell me about baseball",
      "What stocks were mentioned?", 
      "Who needs retirement help?"
    ]
    
    show_context_retrieval(user, example_questions)
  end

  defp call_llm_directly(question) do
    # This calls the LLM without any RAG context for comparison
    case System.get_env("OPENAI_API_KEY") do
      nil ->
        {:error, "OpenAI API key not configured"}
      
      api_key ->
        headers = [
          {"Authorization", "Bearer #{api_key}"},
          {"Content-Type", "application/json"}
        ]
        
        messages = [
          %{role: "system", content: "You are a helpful financial advisor assistant. Answer the user's question based on your general knowledge."},
          %{role: "user", content: question}
        ]
        
        payload = %{
          model: "gpt-4o",
          messages: messages,
          max_tokens: 500,
          temperature: 0.7
        }
        
        case Req.post("https://api.openai.com/v1/chat/completions", headers: headers, json: payload) do
          {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
            {:ok, String.trim(content)}
          
          {:ok, %{status: status, body: body}} ->
            {:error, "OpenAI API error: #{status} - #{inspect(body)}"}
          
          {:error, reason} ->
            {:error, "Network error: #{inspect(reason)}"}
        end
    end
  end
end