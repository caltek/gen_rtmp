defmodule GenRtmp.TcpServer do
  alias GenRtmp.Rtmp.SocketSupervisor
  use Task
  require Logger

  def start_link(_opts) do
    Task.start_link(__MODULE__, :init, [])
  end

  def init() do
    {:ok, socket} = :gen_tcp.listen(1935, [:binary, packet: :raw, active: false, reuseaddr: true])
    Logger.info(tag: "TCP SERVER", msg: "Listening on port 1935")
    accept_loop(socket)
  end

  def accept_loop(socket) do
    {:ok, client} = :gen_tcp.accept(socket)

    socket_handler =
      with {:ok, handler, _info} <- SocketSupervisor.start_socket(client) do
        handler
      else
        {:ok, handler} -> handler
        _ -> nil
      end

    if not is_nil(socket_handler) do
      :gen_tcp.controlling_process(client, socket_handler)
      |> case do
        :ok -> GenServer.call(socket_handler, :controll_granted)
        _ -> :gen_tcp.close(client)
      end
    end

    accept_loop(socket)
  end
end
