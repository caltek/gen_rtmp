defmodule GenRtmp.Rtmp.Messages.Parser do
  require GenRtmp.Rtmp.Messages.Header
  alias GenRtmp.Rtmp.Messages.Media.Video
  alias GenRtmp.Rtmp.Messages.Media.Audio
  alias GenRtmp.Rtmp.Messages.Data.Metadata
  alias GenRtmp.Rtmp.Messages.Control.SetPeerBandwidth
  alias GenRtmp.Rtmp.Messages.Control.WindowAcknowledge
  alias GenRtmp.Rtmp.Messages.Control.UserControl
  alias GenRtmp.Rtmp.Messages.Control.Acknowledge
  alias GenRtmp.Rtmp.Messages.Control.SetChunkSize
  alias GenRtmp.Rtmp.Messages.Command
  alias GenRtmp.Rtmp.Messages.Header
  alias GenRtmp.Rtmp.Socket
  require Logger

  def parse_chunk(%Socket{buffer: packet, prev_chunk_headers: headers} = socket)
      when byte_size(packet) > 0 do
    read_frame(packet, headers, socket.chunk_size)
  end

  def parse_chunk(%Socket{buffer: <<>>}) do
    {:error, :need_more_data}
  end

  defp read_frame(packet, previous_headers, chunk_size) do
    case Header.deserialize(packet, previous_headers) do
      {%Header{} = header, rest} ->
        chunked_body_size = calculate_chunked_body_size(header, chunk_size)

        case rest do
          <<body::binary-size(chunked_body_size), rest::binary>> ->
            combined_body = combine_body_chunks(body, chunk_size, header)
            {:ok, message} = parse_message(header, combined_body)
            {:ok, {header, message, rest}}

          _rest ->
            {:error, :need_more_data}
        end

      {:error, :need_more_data} = error ->
        error
    end
  end

  defp parse_message(%Header{type_id: Header.type(:set_chunk_size)}, packet) do
    with {:ok, {%SetChunkSize{} = message, _rest}} <- SetChunkSize.deserialize(packet) do
      {:ok, message}
    end
  end

  defp parse_message(%Header{type_id: Header.type(:acknowledgement)}, packet) do
    with {:ok, {%Acknowledge{} = message, _rest}} <- Acknowledge.deserialize(packet) do
      {:ok, message}
    end
  end

  defp parse_message(%Header{type_id: Header.type(:user_control_message)}, packet) do
    with {:ok, {%UserControl{} = message, _rest}} <- UserControl.deserialize(packet) do
      {:ok, message}
    end
  end

  defp parse_message(%Header{type_id: Header.type(:window_acknowledgement_size)}, packet) do
    with {:ok, {%WindowAcknowledge{} = message, _rest}} <- WindowAcknowledge.deserialize(packet) do
      {:ok, message}
    end
  end

  defp parse_message(%Header{type_id: Header.type(:set_peer_bandwidth)}, packet) do
    with {:ok, {%SetPeerBandwidth{} = message, _rest}} <- SetPeerBandwidth.deserialize(packet) do
      {:ok, message}
    end
  end

  defp parse_message(%Header{type_id: Header.type(:audio_message)}, packet) do
    with {:ok, {%Audio{} = message, _rest}} <- Audio.deserialize(packet) do
      {:ok, message}
    end
  end

  defp parse_message(%Header{type_id: Header.type(:video_message)}, packet) do
    with {:ok, {%Video{} = message, _rest}} <- Video.deserialize(packet) do
      {:ok, message}
    end
  end

  defp parse_message(%Header{type_id: Header.type(:amf_data)}, packet) do
    metadata = Metadata.deserialize(packet)
    metadata
  end

  defp parse_message(%Header{type_id: Header.type(:amf_command)}, packet) do
    Command.deserialize(packet)
  end

  defp calculate_chunked_body_size(%Header{body_size: body_size} = header, chunk_size) do
    if body_size > chunk_size do
      # if a message's body is greater than the chunk size then
      # after every chunk_size's bytes there is a 0x03 one byte header that
      # needs to be stripped and is not counted into the body_size
      headers_to_strip = div(body_size - 1, chunk_size)

      # if the initial header contains a extended timestamp then
      # every following chunk will contain the timestamp
      timestamps_to_strip = if header.extended_timestamp?, do: headers_to_strip * 4, else: 0

      body_size + headers_to_strip + timestamps_to_strip
    else
      body_size
    end
  end

  # message's size can exceed the defined chunk size
  # in this case the message gets divided into
  # a sequence of smaller packets separated by the a header type 3 byte
  # (the first 2 bits has to be 0b11)
  defp combine_body_chunks(body, chunk_size, header) do
    if byte_size(body) <= chunk_size do
      body
    else
      do_combine_body_chunks(body, chunk_size, header, [])
    end
  end

  defp do_combine_body_chunks(body, chunk_size, header, acc) do
    case body do
      <<body::binary-size(chunk_size), 0b11::2, _chunk_stream_id::6, timestamp::32, rest::binary>>
      when header.extended_timestamp? and timestamp == header.timestamp ->
        do_combine_body_chunks(rest, chunk_size, header, [acc, body])

      # cut out the header byte (staring with 0b11)
      <<body::binary-size(chunk_size), 0b11::2, _chunk_stream_id::6, rest::binary>> ->
        do_combine_body_chunks(rest, chunk_size, header, [acc, body])

      <<_body::binary-size(chunk_size), header_type::2, _chunk_stream_id::6, _rest::binary>> ->
        Logger.warning(tag: "UNEXPECTED HEADER TYPE", msg: header_type)
        IO.iodata_to_binary([acc, body])

      body ->
        IO.iodata_to_binary([acc, body])
    end
  end
end
