defmodule GenRtmp.Rtmp.Socket do
  alias GenRtmp.Rtmp.Messages
  alias GenRtmp.Rtmp.Messages.Header
  alias GenRtmp.Rtmp.PacketHandler
  alias GenRtmp.Rtmp.Handshake
  use GenServer, restart: :transient
  require Logger
  @enforce_keys [:socket]
  defstruct [
    :socket,
    :handshake,
    state: :handshake,
    prev_chunk_headers: nil,
    buffer: <<>>,
    chunk_size: 128,
    packet_drop: 0,
    audio_header: nil,
    video_header: nil,
    flv_header_sent?: false,
    is_controlled: false,
    socket_handler: nil,
    client_info: nil,
    clients: [],
    meta_data: %{}
  ]

  @type t :: %__MODULE__{
          socket: :gen_tcp.socket(),
          state: :handshake | :connecting | :connected | :publishing | :playing,
          flv_header_sent?: boolean,
          handshake: Handshake.t(),
          audio_header: binary(),
          video_header: binary(),
          buffer: binary(),
          chunk_size: integer(),
          prev_chunk_headers: %{required(integer()) => Header.t()} | nil,
          is_controlled: boolean,
          clients: list(),
          packet_drop: integer(),
          client_info: map() | list(map()) | list() | nil,
          meta_data: map(),
          socket_handler: pid() | nil
        }

  @spec start_link(t()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  def init(socket) do
    {:ok, %__MODULE__{socket: socket, state: :handshake, handshake: %Handshake{}}}
  end

  def handle_call(:controll_granted, _from, state) do
    on_socket_controll_granted(state.socket)
    {:reply, :ok, %{state | is_controlled: true, socket_handler: self()}}
  end

  def handle_call(:init_connect, _from, state) do
    {:reply, :ok, state}
  end

  def handle_call(:get_meta_data, _from, state) do
    {:reply,
     {:ok,
      %{
        meta_data: state.meta_data,
        flv_header_sent?: state.flv_header_sent?,
        audio_header: state.audio_header,
        video_header: state.video_header
      }}, state}
  end

  def handle_call({:add_client, client}, _from, state) do
    {:reply, :ok, %{state | clients: [client | state.clients]}}
  end

  def handle_cast({:need_more_data, state}, _state) do
    activate_socket(state.socket)
    {:noreply, state}
  end

  def handle_cast({:register, key}, state) do
    Registry.register(:registry, key, [])
    {:noreply, state}
  end

  def handle_cast(:stop_server, state) do
    :gen_tcp.close(state.socket)
    {:noreply, state}
  end

  def handle_info({:message, {header, message}}, state) do
    Messages.handle_outgoing_messages(state, header, message)
    {:noreply, state}
  end

  def handle_info({:relay, packet}, state) do
    :gen_tcp.send(state.socket, packet)
    {:noreply, state}
  end

  def handle_info(:need_more_data, state) do
    activate_socket(state.socket)
    {:noreply, state}
  end

  def handle_info({:tcp, _socket, packet}, socket_state) do
    nw_state = %{socket_state | buffer: socket_state.buffer <> packet}
    Task.start(fn -> PacketHandler.handle_packet(nw_state) end)
    {:noreply, nw_state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info(tag: "SOCKET HANDLER", msg: "Connection closed", socket: state.socket)
    {:stop, :normal, state}
  end

  def terminate(_reason, state) do
    :gen_tcp.close(state.socket)
  end

  defp on_socket_controll_granted(socket) do
    :inet.setopts(socket, active: :once, nodelay: true, packet: :raw)
  end

  defp activate_socket(socket) do
    :inet.setopts(socket, active: :once)
  end
end
