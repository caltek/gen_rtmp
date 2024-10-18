defmodule GenRtmp.Rtmp.Messages.Control.WindowAcknowledge do
  alias GenRtmp.Rtmp.Messages.Serializer

  defstruct [:size]

  @type t :: %__MODULE__{
          size: integer()
        }

  def deserialize(<<size::32, rest::binary>>), do: {:ok, {%__MODULE__{size: size}, rest}}
  def deserialize(binary) when byte_size(binary) < 4, do: {:error, :need_more_data}

  defimpl Serializer do
    require GenRtmp.Rtmp.Messages.Header
    alias GenRtmp.Rtmp.Messages.Header

    @impl true
    def message_type_id(%@for{}), do: Header.type(:window_acknowledgement_size)
    @impl true
    def serialize(%@for{size: size}), do: <<size::32>>
  end
end
