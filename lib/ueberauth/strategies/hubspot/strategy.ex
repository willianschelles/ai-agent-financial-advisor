defmodule HubspotAuth.HubspotStrategy do
  use Ueberauth.Strategy,
    default_scope: "oauth crm.objects.contacts.read crm.objects.contacts.write",
    uid_field: :user_id,
    # Add this default
    oauth2_module: HubspotAuth.HubspotOAuth

  require Logger
  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra

  def callback_phase!(conn) do
    # Bypass Überauth's default CSRF check entirely
    apply(__MODULE__, :handle_callback!, [conn, conn.params])
  end

  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)
    # Generate a fresh state token
    state = generate_state()
    # state = "TEST_STATE_123"

    opts = [
      redirect_uri: callback_url(conn),
      scope: scopes,
      state: state
    ]

    # Store the state in the session
    conn
    |> put_session("ueberauth.state_param", state)
    # Set cookie explicitly
    |> put_resp_cookie("ueberauth.state_param", state,
      http_only: true,
      same_site: "Lax",
      secure: false
    )
    # Force session save
    |> configure_session(save: :always)
    |> redirect!(apply(option(conn, :oauth2_module), :authorize_url!, [opts]))
  end

  def handle_callback!(conn, params) do
    conn
  end

  def handle_callback!(%Plug.Conn{params: %{"code" => code, "state" => state}} = conn) do
    # Retrieve the stored state from the session
    stored_state = get_session(conn, "ueberauth.state_param")

    if state != stored_state do
      set_errors!(conn, [error("csrf_attack", "Invalid state parameter")])
    else
      module = option(conn, :oauth2_module)
      token_params = [code: code, redirect_uri: callback_url(conn), state: state]

      case apply(module, :get_token, [token_params]) do
        {:ok, response} ->
          Logger.debug("Scopes in token: #{response.token.other_params["scope"]}")
           fetch_user(conn, response.token)
        {:error, reason} -> set_errors!(conn, [error("token_fetch", reason)])
      end
    end
  end

  defp generate_state, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp fetch_user(conn, token) do
    conn
    |> put_private(:hubspot_token, token)

    # |> put_private(:hubspot_user, token.other_params)
  end

  def credentials(conn) do
    token = conn.private.hubspot_token

    %Credentials{
      expires: !!token.expires_at,
      expires_at: token.expires_at,
      scopes: token.other_params["scope"],
      token: token.access_token,
      refresh_token: token.refresh_token,
      token_type: token.token_type
    }
  end

  def info(conn) do
    # user = conn.private.hubspot_user

    %Info{
      email: "user@hubspot.com",
      name: "user name"
    }
  end

  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private.hubspot_token
        # user: conn.private.hubspot_user
      }
    }
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end
end
