defmodule Hedwig.Adapters.Flowdock do
  use Hedwig.Adapter

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
    {:ok, s_conn} = SC.start_link(opts)
    {:ok, r_conn} = RC.start_link(Keyword.put(opts, :s_conn, s_conn))

    {:ok, %State{conn: s_conn, rest_conn: r_conn, opts: opts, robot: robot}}
  end

  def handle_cast({:send, msg}, %{rest_conn: r_conn} = _state) do
    GenServer.cast(r_conn, {:send_message, flowdock_message(msg)})
  end

  def handle_cast({:assign_rest_conn, r_conn}, state) do
    {:noreply, %{state | rest_conn: r_conn}}
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

  def handle_cast({:message, content, flow_id, user, thread_id}, %{robot: robot, users: users} = state) do
    msg = %Hedwig.Message{
      ref: make_ref(),
      room: flow_id,
      private: %{
        thread_id: thread_id
      },
      text: content,
      type: "message",
      user: %Hedwig.User{
        id: user,
        name: users[user]["nick"]
      }
    }

    if msg.text do
      Hedwig.Robot.handle_message(robot, msg)
    end
    {:noreply, state}
  end

  def handle_cast({:flows, flows}, state) do
    new_flows = reduce(flows, state.flows)

    {:noreply, %{state | flows: new_flows}}
  end
  def handle_cast({:users, users}, state) do
    {:noreply, %{state | users: reduce(users, state.users)}}
  end

  def handle_info(:connection_ready, %{robot: robot} = state) do
    Hedwig.Robot.after_connect(robot)
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
