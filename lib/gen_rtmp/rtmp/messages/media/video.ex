defmodule GenRtmp.Rtmp.Messages.Media.Video do
  alias GenRtmp.Rtmp.Messages.Serializer
  defstruct [:data]
  @type t :: %__MODULE__{
          data: binary()
        }

  def deserialize(<<data::binary>>), do: {:ok, {%__MODULE__{data: data}, <<>>}}

  defimpl Serializer do
    alias GenRtmp.Rtmp.Messages.Header
    require Header
    @impl true
    def message_type_id(%@for{}), do: Header.type(:video_message)

    @impl true
    def serialize(%@for{data: data}), do: data
  end
end
