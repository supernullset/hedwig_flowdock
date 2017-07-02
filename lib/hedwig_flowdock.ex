defmodule Hedwig.Adapters.Flowdock do
  use Hedwig.Adapter

  require Logger
  alias Hedwig.Adapters.Flowdock.ConnectionSupervisor, as: CS
  alias Hedwig.Adapters.Flowdock.StreamingConnection, as: SC
  alias Hedwig.Adapters.Flowdock.RestConnection, as: RC

  defmodule State do
    defstruct conn: nil,
      rest_conn: nil,
      flows: %{},
      user_id: nil,
      name: nil,
      opts: nil,
      robot: nil,
      users: %{}
  end

  def init({robot, opts}) do
    Logger.info "Booting up..."
    {:ok, _} = Registry.start_link(:unique, FlowdockConnectionRegistry)

    # TODO: Drop hard link deps on RC and SC calls. lets get this working via registry
    RC.start_link(opts)
    [{r_conn, _}] = Registry.lookup(FlowdockConnectionRegistry, :rest_connection)

    SC.start_link(opts)
    [{s_conn, _}] = Registry.lookup(FlowdockConnectionRegistry, :streaming_connection)

    Kernel.send(self(), :connection_ready)

    user = Enum.find(RC.users, fn u -> u["nick"] == opts[:name] end)

    {:ok, %State{conn: s_conn,
                 rest_conn: r_conn,
                 opts: opts,
                 robot: robot,
                 users: reduce(RC.users, %{}),
                 user_id: user["id"]}}
  end

  def handle_cast({:send, msg}, state) do
    msg
    |> flowdock_message
    |> RC.send_message

    {:noreply, state}
  end

  def handle_cast({:send_raw, msg}, %{rest_conn: r_conn} = state) do
    GenServer.cast(r_conn, {:send_message, msg})

    {:noreply, state}
  end

  def handle_cast({:reply, %{user: user, text: text} = msg}, %{rest_conn: r_conn} = state) do
    msg = %{msg | text: "@#{user.name}: #{text}"}

    GenServer.cast(r_conn, {:send_message, flowdock_message(msg)})
    {:noreply, state}
  end

  def handle_cast({:emote, %{text: text, user: user} = msg}, %{rest_conn: r_conn} = state) do
    msg = %{msg | text: "@#{user.name}: #{text}"}

    GenServer.cast(r_conn, {:send_message, flowdock_message(msg)})
    {:noreply, state}
  end

  def handle_cast({:message, content, flow_id, user, thread_id} = tup, %{robot: robot, users: users} = state) do
    msg = %Hedwig.Message{
      ref: make_ref(),
      room: flow_id,
      private: %{
        thread_id: thread_id
      },
      robot: robot,
      text: content,
      type: "message",
      user: %Hedwig.User{
        id: user,
        name: users[user]["nick"]
      }
    }

    if msg.text do
      Logger.info("source=" <> msg.user.name <> " " <>
                  "text="   <> msg.text      <> " " <>
                  "ref="    <> inspect(msg.ref))

      Hedwig.Robot.handle_in(robot, msg)
    end
    {:noreply, state}
  end

  def handle_call({:flows, flows}, _from, state) do
    {:reply, nil, %{state | flows: flows}}
  end

  def handle_call({:robot_name}, _from, %{opts: opts} = state) do
    {:reply, opts[:name], state}
  end

  def handle_info(:connection_ready, %{robot: robot} = state) do
    Hedwig.Robot.handle_connect(robot)
    {:noreply, state}
  end

  def handle_info(msg, %{robot: robot} = state) do
    Hedwig.Robot.handle_in(robot, msg)
    {:noreply, state}
  end

  defp flowdock_message(%Hedwig.Message{} = msg, overrides \\ %{}) do
    defaults = Map.merge(%{flow: msg.room, content: msg.text, event: msg.type}, overrides)
    if msg.private.thread_id do
      Map.merge(%{thread_id: msg.private[:thread_id]}, defaults)
    end
  end

  defp reduce(collection, acc) do
    Enum.reduce(collection, acc, fn item, acc ->
      Map.put(acc, "#{item["id"]}", item)
    end)
  end

  def parameterize_flow(flow) do
    "#{flow["organization"]["parameterized_name"]}/#{flow["parameterized_name"]}"
  end
end
