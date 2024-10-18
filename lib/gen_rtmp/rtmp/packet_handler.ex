defmodule GenRtmp.Rtmp.PacketHandler do
  alias GenRtmp.Rtmp.Messages
  alias GenRtmp.Rtmp.Handshake
  alias GenRtmp.Rtmp.Socket
  require Logger

  def relay_packet(%Socket{clients: cls}, packet) do
    cls
    |> Enum.each(fn c -> Process.send(c, {:relay, packet}, []) end)
  end

  def handle_packet(%Socket{buffer: buffer, state: :handshake} = socket)
      when byte_size(buffer) > 0 do
    Handshake.rtmp_handshake(socket)
    |> case do
      {:need_more_data, _socket} ->
        GenServer.cast(socket.socket_handler, {:need_more_data, socket})

      {:error, socket, reason} ->
        Logger.error(tag: "SOCKET HANDLER", msg: "Handshake error", reason: reason)
        GenServer.cast(socket.socket_handler, :stop_server)

      {:ok, socket} ->
        handle_packet(socket)
    end
  end

  def handle_packet(%Socket{state: :handshake, buffer: <<>>} = socket),
    do: GenServer.cast(socket.socket_handler, {:need_more_data, socket})

  def handle_packet(%Socket{state: :connecting, buffer: buffer} = socket)
      when byte_size(buffer) > 0 do
    Messages.handle_packet(socket)
  end

  def handle_packet(%Socket{state: :connecting, buffer: <<>>} = socket),
    do: GenServer.cast(socket.socket_handler, {:need_more_data, socket})

  def handle_packet(%Socket{} = socket), do: Messages.handle_packet(socket)
end
