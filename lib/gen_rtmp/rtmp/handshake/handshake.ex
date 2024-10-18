defmodule GenRtmp.Rtmp.Handshake do
  alias GenRtmp.Rtmp.Socket
  require Logger
  defstruct [:rtmp_version, :epoch, state: :handshake_c0_s0]

  @type t :: %__MODULE__{
          rtmp_version: integer(),
          epoch: integer(),
          state: :handshake_c0_s0 | :handshake_c1_s1 | :handshake_c2_s2 | :complete
        }
  @tag :HandShakeProcessor
  @spec rtmp_handshake(any()) ::
          {:ok, Socket.t()} | {:error, Socket.t(), any()} | {:need_more_data, Socket.t()}
  def rtmp_handshake(%Socket{state: socket_state, handshake: %__MODULE__{} = state} = socket) do
    if socket_state == :handshake do
      state.state
      |> case do
        :handshake_c0_s0 -> handshake_c0_s0(socket)
        :handshake_c1_s1 -> handshake_c1_s1(socket)
        :handshake_c2_s2 -> handshake_c2_s2(socket)
      end
    else
      {:ok, socket}
    end
  end

  @spec handshake_c0_s0(Socket.t()) :: {:ok, Socket.t()}
  def handshake_c0_s0(
        %Socket{handshake: %__MODULE__{} = hs_state, buffer: <<3, buffer::binary>>} = state
      ) do
    {:ok,
     %{state | buffer: buffer, handshake: %{hs_state | state: :handshake_c1_s1, rtmp_version: 3}}}
  end

  def handshake_c0_s0(socket, _packet), do: {:error, socket, :invalid_handshake_version}

  def handshake_c1_s1(
        %Socket{buffer: packet, socket: rtmp_socket, handshake: %__MODULE__{} = hs_state} = socket
      ) do
    packet
    |> case do
      <<time::binary-size(4), _time2::binary-size(4), _rest::binary-size(1528), rest::binary>> ->
        :gen_tcp.send(rtmp_socket, <<0x03>>)

        :gen_tcp.send(
          rtmp_socket,
          <<time::binary-size(4), 0::size(32), :crypto.strong_rand_bytes(1528)::binary>>
        )

        :gen_tcp.send(rtmp_socket, packet)

        {:ok,
         %{
           socket
           | buffer: rest,
             handshake: %{
               hs_state
               | epoch: :binary.decode_unsigned(time),
                 state: :handshake_c2_s2
             }
         }}

      binary when byte_size(binary) < 1536 ->
        {:need_more_data, socket}

      other ->
        Logger.warning(
          tag: @tag,
          msg: "invalid handshake packet",
          packet: other,
          size: byte_size(other)
        )

        {:error, socket, :invalid_handshake_state}
    end
  end

  def handshake_c2_s2(%Socket{buffer: packet, handshake: %__MODULE__{} = hs_sate} = state) do
    packet
    |> case do
      <<_time::binary-size(4), _time2::binary-size(4), _rand::binary-size(1528), rest::binary>> ->
        {:ok,
         %{state | state: :connecting, buffer: rest, handshake: %{hs_sate | state: :complete}}}

      binary when byte_size(binary) < 1536 ->
        {:need_more_data, state}

      other ->
        Logger.warning(
          tag: @tag,
          msg: "invalid handshake packet",
          packet: other,
          size: byte_size(other)
        )

        {:error, state, :invalid_handshake_state}
    end
  end
end
