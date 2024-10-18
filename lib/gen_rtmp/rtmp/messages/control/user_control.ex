defmodule GenRtmp.Rtmp.Messages.Control.UserControl do
  alias GenRtmp.Rtmp.Messages.Serializer

  defstruct [:event_id, :data]

  @type t :: %__MODULE__{
          event_id: integer(),
          data: binary()
        }

  defmacro event_id(:streamBegin), do: 0x00
  defmacro event_id(:streamEOF), do: 0x01
  defmacro event_id(:setBufferLength), do: 0x03
  defmacro event_id(:streamIsRecorded), do: 0x01

  def deserialize(<<event_id::16, data::binary>>),
    do: {:ok, {%__MODULE__{event_id: event_id, data: data}, <<>>}}

  def deserialize(binary) when byte_size(binary) < 4, do: {:error, :need_more_data}
  def deserialize(_binary), do: {:error, :invalid_message}

  defimpl Serializer do
    alias GenRtmp.Rtmp.Messages.Header
    require Header

    @impl true
    def message_type_id(%@for{}), do: Header.type(:user_control_message)

    @impl true
    def serialize(%@for{event_id: event_id, data: data}), do: <<event_id::16, data::binary>>
  end
end
