defmodule Hedwig.Adapters.Flowdock.ConnectionSupervisor do
  use Supervisor
  import Supervisor.Spec

  @supervisor_name :hedwig_flowdock_connection_supervisor

  alias Hedwig.Adapters.Flowdock.StreamingConnection, as: SC
  alias Hedwig.Adapters.Flowdock.RestConnection, as: RC

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, [opts], name: @supervisor_name)
  end

  def init(options) do
    children = [supervisor(Registry, [:unique, FlowdockConnectionRegistry]),
                supervisor(RC, options),
                supervisor(SC, options)
               ]
    supervise(children, strategy: :one_for_one)
  end
end
