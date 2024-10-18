defmodule GenRtmp.Rtmp.Messages.Control.SetChunkSize do
  alias GenRtmp.Rtmp.Messages.Serializer
  defstruct [:chunk_size]

  @type t :: %__MODULE__{
          chunk_size: integer()
        }
  def deserialize(<<0x00::1, chunk_size::31, rest::binary>>),
    do: {:ok, {%__MODULE__{chunk_size: chunk_size}, rest}}

  def deserialize(binary) when byte_size(binary) < 4, do: {:error, :need_more_data}

  def deserialize(_binary), do: {:error, :invalid_message}

  defimpl Serializer do
    alias GenRtmp.Rtmp.Messages.Header
    require Header
    @impl true
    def message_type_id(%@for{}), do: Header.type(:set_chunk_size)
    @impl true
    def serialize(%@for{chunk_size: chunk_size}), do: <<0x00::1, chunk_size::31>>
  end
end
