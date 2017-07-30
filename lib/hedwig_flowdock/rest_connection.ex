defmodule Hedwig.Adapters.Flowdock.RestConnection do
  use Connection

  require Logger
  alias Hedwig.Adapters.Flowdock, as: Adapter
  alias Hedwig.Adapters.Flowdock.RestConnection, as: RC

  @timeout 5_000
  @ssl_port 443
  @endpoint "api.flowdock.com"

  defstruct conn: nil,
            host: nil,
            path: nil,
            port: nil,
            ref: nil,
            adapter_pid: nil,
            token: nil,
            query: nil,
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

    initial_state = struct(__MODULE__, opts)

    Connection.start_link(__MODULE__, initial_state, name: name())
  end

  def name do
    {:via, Registry, {FlowdockConnectionRegistry, :rest_connection}}
  end

  def close(pid) do
    Connection.call(pid, :close)
  end

  ### Connection callbacks ###

  def init(state) do
    {:connect, :init, state}
  end

  def users do
    GenServer.call(pid(), :users)
  end

  def flows do
    GenServer.call(pid(), :flows)
  end

  def pid do
    [{pid, _}] = Registry.lookup(FlowdockConnectionRegistry, :rest_connection)
    pid
  end

  def send_message(content) do
    GenServer.cast(pid(), {:send_message, content})
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
            Logger.info "REST connection established"
            new_state = %{state | conn: conn}
            {:ok, new_state} = connect(:flows, new_state)
            connect(:users, new_state)
        after @timeout ->
          Logger.error "Unable to connect"

          {:backoff, @timeout, state}
        end
      {:error, e} = _error ->
        Logger.error inspect(e)
        {:backoff, @timeout, state}
    end
  end

  def connect(:users, %{conn: conn, token: token} = state) do
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

  def connect(:flows, %{conn: conn, token: token} = state) do
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

  def activity(%{users: users, flows: flows, adapter_pid: pid} = state) do
    robot_name = Hedwig.Adapters.Flowdock.robot_name(pid)
    user = Enum.find(users, fn u -> u["nick"] == robot_name end)

    {mega, secs, _} = :erlang.timestamp()
    last_activity = mega*1000000 + secs

    flows
    |> Enum.each(fn (f) ->
      msg = %{flow: parameterize_flow(f), content: %{last_activity: last_activity}, event: "activity.user", user: user["id"]}
      RC.send_message(msg)
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

  def handle_info({:gun_data, conn, _ref, _is_fin, data}, %{adapter_pid: pid} = state) do
    decoded = Poison.decode!(data)

    if decoded["event"] == "message" do
      Adapter.accept_message(pid,
        decoded["content"], decoded["flow"], decoded["user"], decoded["thread_id"])
    end

    {:noreply, %{state | conn: conn}}
  end
end
