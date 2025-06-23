user = AiAgent.Accounts.get_user!(1)
result = AiAgent.LLM.ToolCalling.ask_with_tools(user, "What is the Avenua Connections?")
IO.inspect(result, limit: :infinity)