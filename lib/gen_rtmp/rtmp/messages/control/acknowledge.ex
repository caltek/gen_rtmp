defmodule GenRtmp.Rtmp.Messages.Control.Acknowledge do
  alias GenRtmp.Rtmp.Messages.Serializer
  defstruct [:sequence]

  @type t :: %__MODULE__{
          sequence: integer()
        }
  def deserialize(<<sequence::32, rest::binary>>),
    do: {:ok, {%__MODULE__{sequence: sequence}, rest}}

  def deserialize(binary) when byte_size(binary) < 4, do: {:error, :need_more_data}
  def deserialize(_binary), do: {:error, :invalid_message}

  defimpl Serializer do
    alias GenRtmp.Rtmp.Messages.Header
    require Header
    @impl true
    def message_type_id(%@for{}), do: Header.type(:acknowledgement)

    @impl true
    def serialize(%@for{sequence: sequence}), do: <<sequence::32>>
  end
end
