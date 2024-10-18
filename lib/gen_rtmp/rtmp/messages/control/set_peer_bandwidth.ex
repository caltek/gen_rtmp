defmodule GenRtmp.Rtmp.Messages.Control.SetPeerBandwidth do
  alias GenRtmp.Rtmp.Messages.Serializer

  defstruct [:limit_type, :limit]

  @type t :: %__MODULE__{
          limit_type: integer(),
          limit: integer()
        }

  defmacro limit_type(:hard), do: 0x00
  defmacro limit_type(:soft), do: 0x01
  defmacro limit_type(:dynamic), do: 0x02

  def deserialize(<<limit::32, limit_type::8, rest::binary>>),
    do: {:ok, {%__MODULE__{limit: limit, limit_type: limit_type}, rest}}

  def deserialize(binary) when byte_size(binary) < 4, do: {:error, :need_more_data}
  def deserialize(_binary), do: {:error, :invalid_message}

  defimpl Serializer do
    alias GenRtmp.Rtmp.Messages.Header
    require GenRtmp.Rtmp.Messages.Header
    @impl true
    def message_type_id(%@for{}), do: Header.type(:set_peer_bandwidth)
    @impl true
    def serialize(%@for{limit: limit, limit_type: limit_type}), do: <<limit::32, limit_type::8>>
  end
end
