# defmodule AiAgent.LLM.QuickTest do
#   @moduledoc """
#   Quick testing functions for the RAG system.
#   Use these for rapid testing and debugging.
#   """

#   alias AiAgent.LLM.RAGQuery
#   alias AiAgent.LLM.RAGDemo
#   alias AiAgent.Embeddings.VectorStore
#   alias AiAgent.Embeddings.DataIngestion
#   alias AiAgent.User
#   alias AiAgent.Repo

#   @doc """
#   One-command test of the entire RAG pipeline.

#   ## Usage in IEx:
#   iex> AiAgent.LLM.QuickTest.test_everything()
#   """
#   def test_everything do
#     IO.puts("🚀 === QUICK RAG SYSTEM TEST ===")

#     # Check if we have a user with data
#     case find_user_with_data() do
#       nil ->
#         IO.puts("📊 No user with data found. Running demo setup...")
#         RAGDemo.run_complete_demo()

#       user ->
#         IO.puts("✅ Found user with data: #{user.email}")
#         test_with_user(user)
#     end
#   end

#   @doc """
#   Test RAG with a specific user.
#   """
#   def test_with_user(user) do
#     IO.puts("🧪 Testing RAG with user: #{user.email}")

#     # Check user's document stats
#     stats = VectorStore.get_document_stats(user)
#     IO.puts("📊 User has #{stats.total} documents")

#     if stats.total == 0 do
#       IO.puts("❌ User has no documents. Try ingesting some data first:")
#       IO.puts("   AiAgent.Embeddings.DataIngestion.ingest_gmail_messages(user)")
#       IO.puts("   AiAgent.Embeddings.DataIngestion.ingest_hubspot_data(user)")
#       {:error, "No documents"}
#     end

#     # Test questions
#     test_questions = [
#       "Who mentioned their kid plays baseball?",
#       "What did someone say about AAPL stock?",
#       "Who needs help with retirement planning?",
#       "What meetings are scheduled?",
#       "Tell me about recent emails"
#     ]

#     IO.puts("\n🔍 Testing #{length(test_questions)} questions:")

#     Enum.each(test_questions, fn question ->
#       IO.puts("\n❓ #{question}")

#       case RAGQuery.ask(user, question) do
#         {:ok, result} ->
#           IO.puts("✅ #{String.slice(result.response, 0, 150)}...")
#           IO.puts("   📄 Used #{length(result.context_used)} documents")

#         {:error, reason} ->
#           IO.puts("❌ Error: #{reason}")
#       end
#     end)

#     IO.puts("\n✅ RAG test completed!")
#   end

#   @doc """
#   Quick test with demo data for development.
#   """
#   def quick_demo do
#     IO.puts("⚡ Quick Demo Setup")

#     # Create demo user
#     user = Repo.insert!(%User{
#       email: "quicktest_#{System.system_time(:second)}@example.com",
#       google_tokens: %{"access_token" => "demo"}
#     })

#     # Add some quick test documents
#     demo_docs = [
#       %{
#         content: "My son plays baseball on weekends. He's really getting good at hitting!",
#         source: "parent@example.com",
#         type: "email"
#       },
#       %{
#         content: "I'm considering selling my Apple stock (AAPL). It's up 20% this year.",
#         source: "investor@example.com",
#         type: "email"
#       }
#     ]

#     VectorStore.store_documents_batch(user, demo_docs)

#     # Test a question
#     IO.puts("\n🤔 Testing: 'Who mentioned baseball?'")

#     case RAGQuery.ask(user, "Who mentioned baseball?") do
#       {:ok, result} ->
#         IO.puts("🤖 #{result.response}")
#         IO.puts("📄 Used #{length(result.context_used)} documents")

#       {:error, reason} ->
#         IO.puts("❌ #{reason}")
#     end

#     # Cleanup
#     Repo.delete(user)
#     IO.puts("\n✅ Quick demo completed!")
#   end

#   @doc """
#   Test just the embedding and search parts (no LLM).
#   Useful when OpenAI API key is not available.
#   """
#   def test_search_only(user_email, question) do
#     case Repo.get_by(User, email: user_email) do
#       nil ->
#         IO.puts("❌ User not found: #{user_email}")

#       user ->
#         IO.puts("🔍 Testing search for: '#{question}'")

#         case RAGQuery.get_context_only(user, question) do
#           {:ok, %{documents: docs}} ->
#             IO.puts("✅ Found #{length(docs)} relevant documents:")

#             Enum.each(docs, fn doc ->
#               IO.puts("  📄 #{doc.source} (#{doc.type}) - similarity: #{Float.round(doc.similarity, 3)}")
#               IO.puts("     #{String.slice(doc.content, 0, 100)}...")
#             end)

#           {:error, reason} ->
#             IO.puts("❌ Search failed: #{reason}")
#         end
#     end
#   end

#   @doc """
#   Show all available test functions.
#   """
#   def help do
#     IO.puts("""
#     🛠️  Available RAG Test Functions:

#     ## Quick Tests
#     AiAgent.LLM.QuickTest.test_everything()        # Complete test
#     AiAgent.LLM.QuickTest.quick_demo()             # Fast demo with sample data

#     ## Specific Tests
#     AiAgent.LLM.QuickTest.test_with_user(user)     # Test with specific user
#     AiAgent.LLM.QuickTest.test_search_only(email, question)  # Search only (no LLM)

#     ## Full Demos
#     AiAgent.LLM.RAGDemo.run_complete_demo()        # Comprehensive demo
#     AiAgent.LLM.RAGDemo.test_question(user, "?")   # Test specific question
#     AiAgent.LLM.RAGDemo.benchmark_rag_performance(user)  # Performance test

#     ## Direct Usage
#     user = AiAgent.Repo.get_by(AiAgent.User, email: "your@email.com")
#     AiAgent.LLM.RAGQuery.ask(user, "Your question here")
#     """)
#   end

#   # Private helper functions

#   defp find_user_with_data do
#     # Find a user that has documents
#     users = Repo.all(User)

#     Enum.find(users, fn user ->
#       stats = VectorStore.get_document_stats(user)
#       stats.total > 0
#     end)
#   end
# end
