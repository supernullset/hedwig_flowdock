defmodule Hedwig.Adapters.Flowdock.RestConnection do
  use Connection

  require Logger

  @timeout 5_000
  @endpoint "api.flowdock.com"

  defstruct conn: nil,
            s_conn: nil,
            host: nil,
            path: nil,
            port: nil,
            ref: nil,
            token: nil,
            query: nil,
            owner: nil

  ### PUBLIC API ###

  def start_link(opts) do
    %URI{host: host, port: port, path: path} =
      URI.parse(opts[:endpoint] || @endpoint)

    opts =
      opts
      |> Keyword.put(:host, host)
      |> Keyword.put(:port, 443)
      |> Keyword.put(:path, path)
      |> Keyword.put(:owner, self())

    initial_state = struct(__MODULE__, opts)

    Connection.start_link(__MODULE__, initial_state)
  end

  def close(pid) do
    Connection.call(pid, :close)
  end

  ### Connection callbacks ###

  def init(state) do
    {:connect, :init, state}
  end

  def send_message(conn, message) do
#    ref = :gun.post(conn, to_char_list("/messages"), headers)
  end

  def connect(info, %{host: host, port: port} = state) when info in [:init, :backoff] do
    case :gun.open(to_char_list(@endpoint), port) do
      {:ok, conn} ->
        receive do
          {:gun_up, ^conn, :http} ->
            Logger.info "REST connection established"
            new_state = %{state | conn: conn}
            connect(:users, new_state)
            connect(:flows, new_state)
        after @timeout ->
          Logger.error "Unable to connect"

          {:backoff, @timeout, state}
        end
      {:error, _} = error ->
        {:backoff, @timeout, state}
    end
  end

  def connect(:users, %{conn: conn, token: token, s_conn: s_conn} = state) do
    encoded_pw = Base.encode64(token)
    headers = [{"authorization", "Basic #{encoded_pw}"}]
    
    ref = :gun.get(conn, to_char_list("/users"), headers)
    
    case :gun.await_body(conn, ref) do
      {:ok, body} ->
        decoded = Poison.decode!(body)
        send(s_conn, {:users, decoded})

        {:ok, state}
      {:error, _} = error ->
        {:backoff, @timeout, state}
    end
  end

  def connect(:flows, %{conn: conn, token: token, s_conn: s_conn} = state) do
    encoded_pw = Base.encode64(token)
    headers = [{"authorization", "Basic #{encoded_pw}"}]
    
    ref = :gun.get(conn, to_char_list("/flows"), headers)
    
    case :gun.await_body(conn, ref) do
      {:ok, body} ->
        decoded = Poison.decode!(body)
        send(s_conn, {:flows, decoded})

        {:ok, state}
      {:error, _} = error ->
        {:backoff, @timeout, state}
    end
  end

  #TODO: update
  def disconnect({:close, from}, %{conn: conn} = state) do
    :ok = :gun.close(conn)

    {:stop, :normal, %{state | conn: nil,
                               ref: nil}}
  end

  def disconnect(:reconnect, %{conn: conn} = state) do
    :ok = :gun.close(conn)

    {:connect, :init, %{state | conn: nil,
                                ref: nil}}
  end

  def handle_call(:close, from, state) do
    {:disconnect, {:close, from}, state}
  end

  def handle_info({:gun_response, _, _, _, _, _}, state), do: {:noreply, state}


  def handle_info({:gun_up, conn, :http}, state) do
    {:noreply, %{state | conn: conn}}
  end

  def handle_info({:gun_down, _conn, :http, _reason, _, _} = msg, state) do
    msg |> inspect |> Logger.info

    {:disconnect, :reconnect, state}
  end

  def handle_info({:gun_data, conn, ref, is_fin, "\n"}, state) do
    {:noreply, %{state | conn: conn}}
  end

  def handle_info({:gun_data, conn, ref, is_fin, data}, %{s_conn: s_conn} = state) do
    decoded = Poison.decode!(data)

    if decoded["event"] == "message" do
      send(s_conn, {:message, decoded["content"], decoded["flow"], decoded["user"]})
    end

    {:noreply, %{state | conn: conn}}
  end
end
