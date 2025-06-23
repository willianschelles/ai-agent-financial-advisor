defmodule AiAgent.Rules do
  @moduledoc """
  The Rules context for managing proactive rules.
  """

  import Ecto.Query, warn: false
  alias AiAgent.Repo
  alias AiAgent.Rules.ProactiveRule

  @doc """
  Returns the list of proactive_rules for a user.
  """
  def list_proactive_rules(user_id) do
    ProactiveRule
    |> where([r], r.user_id == ^user_id)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns the list of active proactive_rules for a user.
  """
  def list_active_proactive_rules(user_id) do
    ProactiveRule
    |> where([r], r.user_id == ^user_id and r.is_active == true)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single proactive_rule.
  """
  def get_proactive_rule!(id), do: Repo.get!(ProactiveRule, id)

  @doc """
  Gets a single proactive_rule for a user.
  """
  def get_user_proactive_rule(user_id, id) do
    ProactiveRule
    |> where([r], r.user_id == ^user_id and r.id == ^id)
    |> Repo.one()
  end

  @doc """
  Creates a proactive_rule.
  """
  def create_proactive_rule(attrs \\ %{}) do
    %ProactiveRule{}
    |> ProactiveRule.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a proactive_rule.
  """
  def update_proactive_rule(%ProactiveRule{} = proactive_rule, attrs) do
    proactive_rule
    |> ProactiveRule.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a proactive_rule.
  """
  def delete_proactive_rule(%ProactiveRule{} = proactive_rule) do
    Repo.delete(proactive_rule)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking proactive_rule changes.
  """
  def change_proactive_rule(%ProactiveRule{} = proactive_rule, attrs \\ %{}) do
    ProactiveRule.changeset(proactive_rule, attrs)
  end

  @doc """
  Toggles the active status of a proactive rule.
  """
  def toggle_proactive_rule(%ProactiveRule{} = proactive_rule) do
    update_proactive_rule(proactive_rule, %{is_active: !proactive_rule.is_active})
  end

  @doc """
  Finds matching proactive rules for a given trigger type and user.
  """
  def find_matching_rules(user_id, trigger_type, event_data) do
    ProactiveRule
    |> where([r], r.user_id == ^user_id and r.trigger_type == ^trigger_type and r.is_active == true)
    |> Repo.all()
    |> Enum.filter(&rule_matches_event?(&1, event_data))
  end

  defp rule_matches_event?(%ProactiveRule{trigger_conditions: conditions}, event_data) when is_map(conditions) do
    conditions
    |> Enum.all?(fn {key, expected_value} ->
      case get_in(event_data, String.split(key, ".")) do
        nil -> false
        actual_value -> matches_condition?(actual_value, expected_value)
      end
    end)
  end

  defp rule_matches_event?(_rule, _event_data), do: true

  defp matches_condition?(actual, expected) when is_binary(expected) do
    cond do
      String.starts_with?(expected, "regex:") ->
        regex_pattern = String.slice(expected, 6..-1//1)
        case Regex.compile(regex_pattern) do
          {:ok, regex} -> Regex.match?(regex, to_string(actual))
          {:error, _} -> false
        end
      String.starts_with?(expected, "contains:") ->
        search_term = String.slice(expected, 9..-1//1)
        String.contains?(String.downcase(to_string(actual)), String.downcase(search_term))
      true ->
        to_string(actual) == expected
    end
  end

  defp matches_condition?(actual, expected), do: actual == expected
end