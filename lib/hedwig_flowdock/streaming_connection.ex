defmodule Hedwig.Adapters.Flowdock.StreamingConnection do
  use Connection

  require Logger

  @timeout 5_000
  @endpoint "stream.flowdock.com"

  defstruct conn: nil,
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

  def init(%{token: token, owner: owner} = state) do
    {:connect, :init, state}
  end

  def connect(info, %{host: host, port: port} = state) when info in [:init, :backoff] do
    case :gun.open(to_char_list(@endpoint), port) do
      {:ok, conn} ->
        receive do
          {:gun_up, ^conn, :http} ->
            Logger.info "Streaming connection established"
            connect(:stream_start, %{state | conn: conn})
        after @timeout ->
          Logger.error "Unable to connect"

          {:backoff, @timeout, state}
        end
      {:error, _} = error ->
        {:backoff, @timeout, state}
    end
  end

  def connect(:stream_start, %{conn: conn, query: query, token: token} = state) do
    encoded_pw = Base.encode64(token)
    headers = [{"authorization", "Basic #{encoded_pw}"}, {"connection", "keep-alive"}]
    ref = :gun.get(conn, to_char_list("/flows?#{query}"), headers)

    case :gun.await(conn, ref) do
      {body, is_fin, status, _headers} ->
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


  def handle_cast({:flows, flows}, %{owner: owner} = state) do
    # pull flows into filter here
    query = "filter=#{parameterize_flows(flows)}"
    {:noreply, %{state | query: query}}
  end

  def handle_info({:gun_up, conn, :http}, state) do
    {:noreply, %{state | conn: conn}}
  end

  def handle_info({:gun_down, _conn, :http, _reason, _, _} = msg, state) do
    {:disconnect, :reconnect, state}
  end

  def handle_info({:gun_data, conn, ref, is_fin, "\n"}, state) do
    {:noreply, %{state | conn: conn}}
  end

  def handle_info({:gun_data, conn, ref, is_fin, data}, %{owner: owner} = state) do
    decoded = Poison.decode!(data)
    if decoded["event"] == "message" do
      GenServer.cast(owner, {:message, decoded["content"], decoded["flow"], decoded["user"]})
    end

    {:noreply, %{state | conn: conn}}
  end

  def parameterize_flows(flows) do
    Enum.map(flows, fn d ->
      "#{d["organization"]["parameterized_name"]}/#{d["parameterized_name"]}"
    end)
    |> Enum.join(",")
  end
end
