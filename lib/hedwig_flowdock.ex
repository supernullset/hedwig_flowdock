defmodule Hedwig.Adapters.Flowdock do
  use Hedwig.Adapter
  require Logger

  alias Hedwig.Adapters.Flowdock.StreamingConnection, as: SC
  alias Hedwig.Adapters.Flowdock.RestConnection, as: RC

  defmodule State do
    # FIXME: convert this to flowdock state object
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

  def handle_cast({:send, msg}, %{rest_conn: r_conn} = state) do

    RC.send_message(r_conn, flowdock_message(msg))
  end

  def handle_cast({:assign_rest_conn, r_conn}, state) do
    {:noreply, %{state | rest_conn: r_conn}}
  end

  # TODO: update format
  def handle_cast({:reply, %{user: user, text: text} = msg}, %{conn: conn, users: users} = state) do
    Logger.info "yep im replyin"

    msg = %{msg | text: "<@#{user.id}|#{user.name}>: #{text}"} # TODO: make sure msg post format is what it needs to be for flowdock

    Logger.info flowdock_message(msg)

    RC.send_message(conn, flowdock_message(msg))
  end

  # TODO: update format
  def handle_cast({:emote, %{text: text} = msg}, %{conn: conn} = state) do
    RC.send_message(conn, flowdock_message(msg, %{subtype: "me_message"})) #TODO: make this flowdock specific
  end

  # TODO: update format
#  def handle_info(%{"subtype" => "flow_join", "flow" => flow, "user" => user} = msg, state) do
#    flows = put_flow_user(state.flows, flow, user)
#    {:noreply, %{state | flows: flows}}
#  end
#
#  # TODO: update format
#  def handle_info(%{"subtype" => "flow_leave", "flow" => flow, "user" => user} = msg, state) do
#    flows = delete_flow_user(state.flows, flow, user)
#    {:noreply, %{flows | flows: flows}}
#  end

  def handle_cast({:message, content, flow, user}, %{conn: conn, robot: robot, users: users} = state) do

    msg = %Hedwig.Message{
      ref: make_ref(),
      room: flow,
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
    msg |> inspect |> Logger.info
    {:noreply, state}
  end

  def handle_cast({:flows, flows}, %{conn: conn} = state) do
    reduce(flows, state.flows) |> inspect |> Logger.info

    new_flows = reduce(flows, state.flows)

    {:noreply, %{state | flows: new_flows}}
  end

  # TODO: update format
  def handle_info({:self, %{"id" => id, "name" => name}}, state) do
    {:noreply, %{state | id: id, name: name}}
  end

  def handle_cast({:users, users}, state) do
    {:noreply, %{state | users: reduce(users, state.users)}}
  end

  # TODO: update format
  def handle_info(%{"type" => "presence_change", "user" => user}, %{id: user} = state), do:
    {:noreply, state}
  # TODO: update format

  def handle_info(%{"presence" => presence, "type" => "presence_change", "user" => user}, state) do
    users = update_in(state.users, [user], &Map.put(&1, "presence", presence))
    {:noreply, %{state | users: users}}
  end

  # TODO: update format
  def handle_info(%{"type" => "reconnect_url"}, state), do:
    {:noreply, state}

  # TODO: update format
  def handle_info(:connection_ready, %{robot: robot} = state) do
    Hedwig.Robot.after_connect(robot)
    {:noreply, state}
  end

  # TODO: update format
  def handle_info(msg, %{robot: robot} = state) do
    Hedwig.Robot.handle_in(robot, msg)
    {:noreply, state}
  end
  # TODO: update format
  defp flowdock_message(%Hedwig.Message{} = msg, overrides \\ %{}) do
    #TODO: make this flowdock specific
    Map.merge(%{flow: msg.room, text: msg.text, type: msg.type}, overrides)
  end
  # TODO: update format
  defp put_flow_user(flows, flow_id, user_id) do
    update_in(flows, [flow_id, "members"], &([user_id | &1]))
  end
  # TODO: update format
  defp delete_flow_user(flows, flow_id, user_id) do
    update_in(flows, [flow_id, "members"], &(&1 -- [user_id]))
  end
  # TODO: update format
  defp reduce(collection, acc) do
    Enum.reduce(collection, acc, fn item, acc ->
      Map.put(acc, "#{item["id"]}", item)
    end)
  end
end
