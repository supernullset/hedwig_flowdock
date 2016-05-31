defmodule Hedwig.Adapters.Flowdock do
  use Hedwig.Adapter

  alias Hedwig.Adapters.Flowdock.Connection

  defmodule State do
    # FIXME: convert this to flowdock state object
    defstruct conn: nil,
      flows: %{},
      orgs: %{},
      user_id: nil,
      name: nil,
      opts: nil,
      robot: nil,
      users: %{}    
  end


  defp flow_query({} = state) do
    "filter=pwd-whoami/bruce-testing"
  end

  def init({robot, opts}) do
    {:ok, conn} = Connection.start_link(opts)
    {:ok, %State{conn: conn, opts: opts, robot: robot}}
  end

  def handle_cast({:send, msg}, %{conn: conn} = state) do
    Connection.send_message(conn, flowdock_message(msg))
  end

  # TODO: update format
  def handle_cast({:reply, %{user: user, text: text} = msg}, %{conn: conn, users: users} = state) do
    msg = %{msg | text: "<@#{user.id}|#{user.name}>: #{text}"} # TODO: make sure msg post format is what it needs to be for flowdock
    Connection.send_message(conn, flowdock_message(msg))
  end

  # TODO: update format
  def handle_cast({:emote, %{text: text} = msg}, %{conn: conn} = state) do
    Connection.send_message(conn, flowdock_message(msg, %{subtype: "me_message"})) #TODO: make this flowdock specific
  end

  # TODO: update format
  def handle_info(%{"subtype" => "channel_join", "channel" => channel, "user" => user} = msg, state) do
    channels = put_channel_user(state.channels, channel, user)
    {:noreply, %{state | channels: channels}}
  end

  # TODO: update format
  def handle_info(%{"subtype" => "channel_leave", "channel" => channel, "user" => user} = msg, state) do
    channels = delete_channel_user(state.channels, channel, user)
    {:noreply, %{state | channels: channels}}
  end

  # TODO: update format
  def handle_info(%{"type" => "message", "user" => user} = msg, %{conn: conn, robot: robot, users: users} = state) do
    msg = %Hedwig.Message{
      ref: make_ref(),
      room: msg["channel"],
      text: msg["text"],
      type: "message",
      user: %Hedwig.User{
        id: user,
        name: users[user]["name"]
      }
    }

    if msg.text do
      Hedwig.Robot.handle_message(robot, msg)
    end

    {:noreply, state}
  end  

  # TODO: update format
  def handle_info({:channels, channels}, state) do
    {:noreply, %{state | channels: reduce(channels, state.channels)}}
  end
  # TODO: update format
  def handle_info({:groups, groups}, state) do
    {:noreply, %{state | groups: reduce(groups, state.groups)}}
  end
  # TODO: update format
  def handle_info({:self, %{"id" => id, "name" => name}}, state) do
    {:noreply, %{state | id: id, name: name}}
  end
  # TODO: update format
  def handle_info({:users, users}, state) do
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
    Map.merge(%{channel: msg.room, text: msg.text, type: msg.type}, overrides)
  end
  # TODO: update format
  defp put_channel_user(channels, channel_id, user_id) do
    update_in(channels, [channel_id, "members"], &([user_id | &1]))
  end
  # TODO: update format
  defp delete_channel_user(channels, channel_id, user_id) do
    update_in(channels, [channel_id, "members"], &(&1 -- [user_id]))
  end
  # TODO: update format
  defp reduce(collection, acc) do
    # TODO: What does this do? it seems like its accumulating ids...
    Enum.reduce(collection, acc, fn item, acc ->
      Map.put(acc, item["id"], item)
    end)
  end
end
