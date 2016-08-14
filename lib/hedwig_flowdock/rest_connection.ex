defmodule Hedwig.Adapters.Flowdock.RestConnection do
  use Connection

  require Logger

  @timeout 5_000
  @ssl_port 443
  @endpoint "api.flowdock.com"

  defstruct conn: nil,
            host: nil,
            path: nil,
            port: nil,
            ref: nil,
            token: nil,
            query: nil,
            owner: nil,
            users: nil,
            flows: nil

  ### PUBLIC API ###

  def start_link(opts) do
    %URI{host: host, path: path} =
      URI.parse(opts[:endpoint] || @endpoint)

    opts =
      opts
      |> Keyword.put(:host, host)
      |> Keyword.put(:port, @ssl_port)
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

  def handle_cast({:send_message, message}, %{token: token, conn: conn} = state) do
    encoded_pw = Base.encode64(token)
    headers = [{"authorization", "Basic #{encoded_pw}"}, {"content-type", "application/json"}]
    {:ok, j_message} = Poison.encode(message)
    :gun.post(conn, to_char_list("/messages"), headers, j_message)
    {:noreply, state}
  end

  def connect(info, %{host: _host, port: port} = state) when info in [:init, :backoff] do
    case :gun.open(to_char_list(@endpoint), port) do
      {:ok, conn} ->
        receive do
          {:gun_up, ^conn, :http} ->
            new_state = %{state | conn: conn}
            {:ok, new_state} = connect(:flows, new_state)
            connect(:users, new_state)
        after @timeout ->
          Logger.error "Unable to connect"

          {:backoff, @timeout, state}
        end
      {:error, _} = _error ->
        {:backoff, @timeout, state}
    end
  end

  def connect(:users, %{conn: conn, token: token, owner: _owner} = state) do
    encoded_pw = Base.encode64(token)
    headers = [{"authorization", "Basic #{encoded_pw}"}]

    ref = :gun.get(conn, to_char_list("/users"), headers)

    case :gun.await_body(conn, ref) do
      {:ok, body} ->
        decoded = Poison.decode!(body)
        {:ok, %{state | users: decoded}}
      {:error, _} = _error ->
        {:backoff, @timeout, state}
    end
  end

  def connect(:flows, %{conn: conn, token: token, owner: _owner} = state) do
    encoded_pw = Base.encode64(token)
    headers = [{"authorization", "Basic #{encoded_pw}"}]

    ref = :gun.get(conn, to_char_list("/flows"), headers)

    case :gun.await_body(conn, ref) do
      {:ok, body} ->
        decoded = Poison.decode!(body)

        {:ok, %{ state | flows: decoded}}
      {:error, _} = _error ->
        {:backoff, @timeout, state}
    end
  end

  def activity(%{users: users, owner: owner, flows: flows} = state) do
    robot_name = GenServer.call(owner, {:robot_name})
    user = Enum.find(users, fn u -> u["nick"] == robot_name end)

    user |> inspect |> Logger.info
    {mega, secs, _} = :erlang.timestamp()
    last_activity = mega*1000000 + secs

    flows
    |> Enum.each(fn (f) ->
      msg = %{flow: parameterize_flow(f), content: %{last_activity: last_activity}, event: "activity.user", user: user["id"]}
      GenServer.cast(owner, {:send_raw, msg})
    end)

    {:ok, state}
  end

  def parameterize_flow(flow) do
    "#{flow["organization"]["parameterized_name"]}/#{flow["parameterized_name"]}"
  end

  def disconnect({:close, _from}, %{conn: conn} = state) do
    :ok = :gun.close(conn)

    {:stop, :normal, %{state | conn: nil,
                               ref: nil}}
  end

  def disconnect(:reconnect, %{conn: conn} = state) do
    :ok = :gun.close(conn)

    {:connect, :init, %{state | conn: nil,
                                ref: nil}}
  end

  def handle_call(:flows, _from , %{flows: flows} = state) do
    {:reply, flows, state}
  end

  def handle_call(:users, _from , %{users: users} = state) do
    {:reply, users, state}
  end

  def handle_call(:close, from, state) do
    {:disconnect, {:close, from}, state}
  end

  def handle_info({:gun_response, _, _, _, _, _}, state), do: {:noreply, state}


  def handle_info({:gun_up, conn, :http}, state) do
    {:noreply, %{state | conn: conn}}
  end

  def handle_info({:gun_down, _conn, :http, _reason, _, _} = _msg, state) do
    {:disconnect, :reconnect, state}
  end

  def handle_info({:gun_data, conn, _ref, _is_fin, "\n"}, state) do
    {:noreply, %{state | conn: conn}}
  end

  def handle_info({:gun_data, conn, _ref, _is_fin, data}, %{owner: owner} = state) do
    decoded = Poison.decode!(data)

    if decoded["event"] == "message" do
      GenServer.cast(owner, {:message, decoded["content"], decoded["flow"], decoded["user"], decoded["thread_id"]})
    end

    {:noreply, %{state | conn: conn}}
  end
end
