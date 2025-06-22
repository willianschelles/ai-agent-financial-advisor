defmodule HubspotAuth.HubspotOAuth do
  use OAuth2.Strategy

  @defaults [
    strategy: __MODULE__,
    site: "https://api.hubapi.com",
    authorize_url: "https://app.hubspot.com/oauth/authorize",
    token_url: "https://api.hubapi.com/oauth/v1/token"
  ]

  def client(opts \\ []) do
    config = Application.get_env(:ueberauth, __MODULE__)
    opts = @defaults |> Keyword.merge(config) |> Keyword.merge(opts)

    OAuth2.Client.new(opts)
  end

  def authorize_url!(params \\ [], opts \\ []) do
    opts
    |> client
    |> OAuth2.Client.authorize_url!(params)
  end

  def get_token!(params \\ [], opts \\ []) do
    headers = Keyword.get(opts, :headers, [])
    opts = Keyword.get(opts, :options, [])
    client_options = Keyword.get(opts, :client_options, [])
    client = OAuth2.Client.get_token!(client(client_options), params, headers, opts)

    case client do
      %{token: %{access_token: nil}} -> client
      %{token: token} -> %{client | token: %{token | token_type: "Bearer"}}
    end
  end

  # Strategy callbacks
  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  def get_token(params, opts \\ []) do
    headers = Keyword.get(opts, :headers, [{"Accept", "application/json"}])
    client = client(Keyword.get(opts, :client_options, []))

    case OAuth2.Client.get_token(client, params, headers) do
      {:ok, %{token: token} = response} ->
        {:ok, %{response | token: %{token | token_type: "Bearer"}}}

      {:error, %OAuth2.Response{} = response} ->
        {:error, response}

      error ->
        error
    end
  end

  def get_token(client, params, headers) do
    client
    |> put_param(:client_secret, client.client_secret)
    |> put_header("Accept", "application/json")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end
end
