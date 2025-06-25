defmodule HubspotAuth.HubspotStrategy do
  use Ueberauth.Strategy,
    default_scope:
      "oauth crm.objects.contacts.read crm.objects.contacts.write crm.dealsplits.read_write crm.lists.read crm.lists.write crm.objects.appointments.read crm.objects.appointments.write crm.objects.carts.read crm.objects.commercepayments.read crm.objects.commercepayments.write crm.objects.companies.write crm.objects.courses.read crm.objects.courses.write crm.objects.custom.read crm.objects.custom.write crm.objects.deals.read crm.objects.deals.write crm.objects.feedback_submissions.read crm.objects.goals.read crm.objects.goals.write crm.objects.leads.read crm.objects.leads.write crm.objects.line_items.read crm.objects.line_items.write crm.objects.listings.read crm.objects.listings.write crm.objects.products.read crm.objects.products.write crm.objects.services.read crm.objects.services.write crm.objects.users.read crm.objects.users.write",
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
    redirect_uri =
      System.get_env("HUBSPOT_REDIRECT_URI") ||
        "https://ai-agent-financial-advisor.onrender.com/auth/hubspot/callback"

    opts = [
      redirect_uri: redirect_uri,
      scope: scopes,
      state: state
    ]

    # Store the state in the session
    conn
    |> put_session("ueberauth.state_param", state)
    # Set cookie explicitly (secure: true for production HTTPS)
    |> put_resp_cookie("ueberauth.state_param", state,
      http_only: true,
      same_site: "Lax",
      secure: Application.get_env(:ai_agent, AiAgentWeb.Endpoint)[:url][:scheme] == "https"
    )
    # Force session save
    |> configure_session(save: :always)
    |> redirect!(apply(option(conn, :oauth2_module), :authorize_url!, [opts]))
  end

  def handle_callback!(%Plug.Conn{params: %{"code" => code, "state" => state}} = conn) do
    # Retrieve the stored state from the session
    stored_state = get_session(conn, "ueberauth.state_param")

    if state != stored_state do
      set_errors!(conn, [error("csrf_attack", "Invalid state parameter")])
    else
      module = option(conn, :oauth2_module)

      redirect_uri =
        System.get_env("HUBSPOT_REDIRECT_URI") ||
          "https://ai-agent-financial-advisor.onrender.com/auth/hubspot/callback"

      IO.inspect(redirect_uri, label: "Redirect URI")

      token_params = [
        code: code,
        redirect_uri: redirect_uri,
        state: state
      ]

      case apply(module, :get_token, [token_params]) do
        {:ok, response} ->
          Logger.debug("Scopes in token: #{response.token.other_params["scope"]}")
          fetch_user(conn, response.token)

        {:error, reason} ->
          set_errors!(conn, [error("token_fetch", reason)])
      end
    end
  end

  def handle_callback!(conn, _params) do
    set_errors!(conn, [error("missing_code", "No authorization code received")])
  end

  defp generate_state, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp fetch_user(conn, token) do
    # First, store the token in the connection
    conn = conn |> put_private(:hubspot_token, token)

    # Then create the auth struct using the updated connection
    auth = %Ueberauth.Auth{
      provider: :hubspot,
      strategy: __MODULE__,
      uid: token.other_params["user_id"],
      credentials: credentials(conn),
      info: info(conn),
      extra: extra(conn)
    }

    # Finally, store the auth struct
    conn |> put_private(:ueberauth_auth, auth)
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
