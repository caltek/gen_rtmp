defmodule GenRtmp.Rtmp.SocketSupervisor do
  alias GenRtmp.Rtmp.Socket
  use DynamicSupervisor

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [], name: :sock_sup)
  end

  def start_socket(socket) do
    DynamicSupervisor.start_child(:sock_sup, {Socket, socket})
  end

  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
