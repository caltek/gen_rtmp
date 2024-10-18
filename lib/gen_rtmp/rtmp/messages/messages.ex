defmodule GenRtmp.Rtmp.Messages do
  @moduledoc false
  require GenRtmp.Rtmp.Messages.Header
  require GenRtmp.Rtmp.Messages.Control.SetPeerBandwidth
  require Logger
  require GenRtmp.Rtmp.Messages.Control.UserControl
  alias GenRtmp.Rtmp.Messages.Media.Video
  alias GenRtmp.Rtmp.Messages.Media.Audio
  alias GenRtmp.Rtmp.Messages.Data.Metadata
  alias GenRtmp.Rtmp.Messages.Control.SetChunkSize
  alias GenRtmp.Rtmp.Messages.Control.UserControl
  alias GenRtmp.Rtmp.Messages.Serializer
  alias GenRtmp.Rtmp.Messages.Header
  alias GenRtmp.Rtmp.Messages.Control.SetPeerBandwidth
  alias GenRtmp.Rtmp.Messages.Control.WindowAcknowledge
  alias GenRtmp.Rtmp.Messages.Parser
  alias GenRtmp.Rtmp.Socket
  alias GenRtmp.Rtmp.Messages.Command
  @window_acknowledge_size 2_147_483_647
  @peer_bandwidth_size 2_147_483_647
  @server_chunk_size 4096
  def handle_packet(%Socket{} = socket) do
    Parser.parse_chunk(socket)
    |> case do
      {:ok, {header, message, rest}} ->
        handle_message(socket, header, message)
        |> case do
          {:ok, socket} ->
            up_header = update_header(socket.prev_chunk_headers, header)
            handle_packet(%Socket{socket | buffer: rest, prev_chunk_headers: up_header})
        end

      {:error, :need_more_data} ->
        GenServer.cast(socket.socket_handler, {:need_more_data, socket})
    end
  end

  def handle_message(socket, header, %SetChunkSize{} = control) do
    handle_set_chunk_size(socket, header, control)
  end

  def handle_message(socket, header, %Command{command: command} = message) do
    command
    |> case do
      "connect" ->
        handle_connect_command(socket, header, message)

      "releaseStream" ->
        handle_release_command(socket, header, message)

      "FCPublish" ->
        handle_fc_publish_command(socket, header, message)

      "createStream" ->
        handle_create_stream(socket, header, message)

      "publish" ->
        handle_publish_command(socket, header, message)

      "_checkbw" ->
        handle_check_bw_command(socket, header, message)

      "getStreamLength" ->
        handle_get_stream_length(socket, header, message)

      "play" ->
        handle_play_command(socket, header, message)
    end
  end

  def handle_message(socket, header, %WindowAcknowledge{} = control) do
    handle_window_acknowledge(socket, header, control)
  end

  def handle_message(socket, _header, %Metadata{} = message) do
    Logger.info(tag: "MESSAGE-HANDLER", msg: "Metadata received", metadata: message)
    {:ok, %{socket | meta_data: message}}
  end

  def handle_message(
        %Socket{clients: clients, audio_header: audio_header, video_header: video_header} =
          socket,
        %Header{} = header,
        %module{} = message
      )
      when module in [Audio, Video] do
    cond do
      is_nil(audio_header) and module == Audio ->
        Logger.info(tag: "MESSAGE-HANDLER", msg: "Audio Header received")
        IO.inspect(message.data, limit: :infinity)
        {:ok, %{socket | audio_header: message, flv_header_sent?: not is_nil(video_header)}}

      is_nil(video_header) and module == Video ->
        Logger.info(tag: "MESSAGE-HANDLER", msg: "Vide Header received")
        IO.inspect(message.data, limit: :infinity)
        {:ok, %{socket | video_header: message, flv_header_sent?: not is_nil(audio_header)}}

      true ->
        dispatch(clients, header, message)
        {:ok, socket}
    end
  end

  def handle_message(socket, _header, _message) do
    {:ok, socket}
  end

  def handle_outgoing_messages(%Socket{} = socket, %Header{} = header, message) do
    send_message(socket, message,
      chunk_stream_id: header.chunk_stream_id,
      timestamp: header.timestamp,
      timestamp_delta: header.timestamp_delta,
      extended_timestamp?: header.extended_timestamp?
    )

    {:ok, socket}
  end

  def handle_connect_command(%Socket{} = socket, %Header{stream_id: stream_id}, %Command{
        command: "connect",
        args: args
      }) do
    # TODO: Validate args
    [
      %WindowAcknowledge{size: @window_acknowledge_size},
      %SetPeerBandwidth{
        limit_type: SetPeerBandwidth.limit_type(:dynamic),
        limit: @peer_bandwidth_size
      },
      %UserControl{event_id: UserControl.event_id(:streamBegin), data: <<stream_id::32>>},
      %SetChunkSize{chunk_size: @server_chunk_size}
    ]
    |> Enum.each(&send_message(socket, &1, chunk_stream_id: 2))

    [
      %Command{
        command: "_result",
        transaction_id: 1,
        args: [
          %{
            "fmsVer" => "FMS/3,0,1,123",
            "capabilities" => 31.0
          },
          %{
            "level" => "status",
            "code" => "NetConnection.Connect.Success",
            "description" => "Connection succeeded.",
            "objectEncoding" => 0.0
          }
        ]
      },
      %Command{
        command: "onBWDone",
        transaction_id: 0,
        args: [:null, 8192.0]
      }
    ]
    |> Enum.each(&send_message(socket, &1, chunk_stream_id: 3))

    {:ok, %{socket | client_info: List.first(args)}}
  end

  def handle_release_command(
        %Socket{} = socket,
        %Header{} = _header,
        %Command{command: "releaseStream", transaction_id: transaction_id}
      ) do
    %Command{
      command: "_result",
      transaction_id: transaction_id,
      args: [0.0, :null]
    }
    |> then(&send_message(socket, &1, chunk_stream_id: 3))

    {:ok, socket}
  end

  def handle_fc_publish_command(
        %Socket{} = socket,
        %Header{} = _header,
        %Command{command: "FCPublish", transaction_id: transaction_id}
      ) do
    %Command{
      command: "onFCPublish",
      transaction_id: transaction_id,
      args: []
    }
    |> then(&send_message(socket, &1, chunk_stream_id: 3))

    {:ok, socket}
  end

  def handle_create_stream(
        %Socket{} = socket,
        %Header{stream_id: _stream_id} = _header,
        %Command{command: "createStream", transaction_id: transaction_id}
      ) do
    %Command{
      command: "_result",
      transaction_id: transaction_id,
      args: []
    }
    |> then(&send_message(socket, &1, chunk_stream_id: 3))

    {:ok, socket}
  end

  def handle_publish_command(
        %Socket{} = socket,
        %Header{stream_id: stream_id} = _header,
        %Command{command: "publish", args: [_null, stream_key | args]}
      ) do
    # TODO hook on publish event
    Logger.info(tag: "Messages", msg: "publish", args: args)

    %UserControl{
      event_id: UserControl.event_id(:streamBegin),
      data: <<stream_id::32>>
    }
    |> then(&send_message(socket, &1, chunk_stream_id: 2))

    %Command{
      command: "onStatus",
      transaction_id: 0,
      args: [
        :null,
        %{
          "level" => "status",
          "code" => "NetStream.Publish.Start",
          "description" => "#{stream_key} is now published",
          "details" => stream_key
        }
      ]
    }
    |> then(&send_message(socket, &1, chunk_stream_id: 3, stream_id: stream_id))

    GenServer.cast(socket.socket_handler, {:register, {stream_key, "publisher"}})
    {:ok, %{socket | state: :publishing}}
  end

  def handle_play_command(
        %Socket{} = socket,
        %Header{stream_id: stream_id} = _header,
        %Command{command: "play", args: [_null, stream_key | _args]}
      ) do
    # TODO hook on play event
    %UserControl{
      event_id: UserControl.event_id(:streamBegin),
      data: <<stream_id::32>>
    }
    |> then(&send_message(socket, &1, chunk_stream_id: 2))

    # check if stream exists
    Registry.lookup(:registry, {stream_key, "publisher"})
    |> List.first()
    |> case do
      nil ->
        %Command{
          command: "onStatus",
          transaction_id: 0,
          args: [
            :null,
            %{
              "level" => "status",
              "code" => "NetStream.Play.StreamNotFound",
              "description" => "#{stream_key} is not found or not published",
              "details" => stream_key
            }
          ]
        }
        |> then(&send_message(socket, &1, chunk_stream_id: 3, stream_id: stream_id))

      {publisher, _} ->
        %Command{
          command: "onStatus",
          transaction_id: 0,
          args: [
            :null,
            %{
              "level" => "status",
              "code" => "NetStream.Play.Start",
              "description" => "#{stream_key} is not found or not published",
              "details" => stream_key
            }
          ]
        }
        |> then(&send_message(socket, &1, chunk_stream_id: 3, stream_id: stream_id))

        {:ok, %{meta_data: metadata, audio_header: audio_header, video_header: video_header}} =
          GenServer.call(publisher, :get_meta_data)

        metadata
        |> then(&send_message(socket, &1, chunk_stream_id: 2, stream_id: stream_id))

        audio_header
        |> then(&send_message(socket, &1, chunk_stream_id: 4, stream_id: stream_id))

        video_header
        |> then(&send_message(socket, &1, chunk_stream_id: 6, stream_id: stream_id))

        GenServer.call(publisher, {:add_client, socket.socket_handler})
    end

    {:ok, %{socket | state: :playing}}
  end

  def handle_get_stream_length(
        %Socket{} = socket,
        %Header{} = _header,
        %Command{command: "getStreamLength"}
      ) do
    {:ok, socket}
  end

  def handle_check_bw_command(
        %Socket{} = socket,
        %Header{} = _header,
        %Command{command: "_checkbw", transaction_id: transaction_id}
      ) do
    Logger.info(tag: "Messages", msg: "check_bw")

    %Command{
      command: "_result",
      transaction_id: transaction_id,
      args: [:null, 0.0]
    }
    |> then(&send_message(socket, &1, chunk_stream_id: 3))

    {:ok, socket}
  end

  def handle_window_acknowledge(
        %Socket{} = socket,
        %Header{} = _header,
        %WindowAcknowledge{size: size}
      ) do
    Logger.info(tag: "Messages", msg: "window_acknowledge", size: size)
    {:ok, %{socket | state: :connected}}
  end

  def handle_set_chunk_size(
        %Socket{} = socket,
        %Header{} = _header,
        %SetChunkSize{chunk_size: chunk_size}
      ) do
    Logger.info(tag: "Messages", msg: "set_chunk_size", chunk_size: chunk_size)
    {:ok, %{socket | chunk_size: chunk_size}}
  end

  defp send_message(%Socket{socket: socket}, message, opts) do
    body = Serializer.serialize(message)
    chunk_stream_id = Keyword.get(opts, :chunk_stream_id, 2)

    header =
      opts
      |> Keyword.get(:header)
      |> case do
        nil ->
          message_type = Serializer.message_type_id(message)

          [chunk_stream_id: chunk_stream_id, type_id: message_type, body_size: byte_size(body)]
          |> Keyword.merge(opts)
          |> Header.new()
          |> Header.serialize()

        %Header{} = opt_header ->
          Header.serialize(opt_header)
      end

    payload =
      [header | chunk_payload(body, chunk_stream_id, @server_chunk_size)] |> IO.iodata_to_binary()

    Logger.info(tag: "Messages", msg: "sending message", message: message, payload: payload)
    :gen_tcp.send(socket, payload)
  end

  defp update_header(previous_header, %Header{} = header) when is_map(previous_header) do
    previous_header
    |> Map.put(header.chunk_stream_id, header)
  end

  defp update_header(_previous_header, %Header{} = header),
    do: %{header.chunk_stream_id => header}

  defp chunk_payload(payload, chunk_stream_id, chunk_size, acc \\ []) do
    case {payload, acc} do
      {<<chunk::binary-size(chunk_size), rest::binary>>, []} ->
        chunk_payload(rest, chunk_stream_id, chunk_size, [chunk])

      {<<chunk::binary-size(chunk_size), rest::binary>>, acc} ->
        chunk_payload(rest, chunk_stream_id, chunk_size, [
          acc,
          chunk_separator(chunk_stream_id),
          chunk
        ])

      {payload, []} ->
        [payload]

      {payload, acc} ->
        [acc, chunk_separator(chunk_stream_id), payload]
    end
  end

  defp chunk_separator(chunk_stream_id), do: <<0b11::2, chunk_stream_id::6>>

  defp dispatch(clients, header, message) when is_list(clients) do
    clients
    |> Enum.filter(&is_pid/1)
    |> Enum.each(fn pid -> Process.send(pid, {:message, {header, message}}, [:noconnect]) end)
  end
end
