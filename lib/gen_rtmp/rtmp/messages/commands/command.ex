defmodule GenRtmp.Rtmp.Messages.Command do
  alias GenRtmp.Rtmp.Messages.Serializer
  alias GenRtmp.Rtmp.Messages.Amf.Parser
  @transaction_id 1.0
  defstruct [:args, :command, transaction_id: @transaction_id]

  @type t :: %__MODULE__{
          command: binary(),
          transaction_id: integer(),
          args: map() | list(map()) | list()
        }

  def deserialize(binary) do
    with [command, transaction_id | args] <- Parser.parse(binary) do
      {:ok, %__MODULE__{command: command, transaction_id: transaction_id, args: args}}
    end
  end

  defimpl Serializer do
    alias GenRtmp.Rtmp.Messages.Amf.Encoder
    alias GenRtmp.Rtmp.Messages.Header
    require Header

    @impl true
    def message_type_id(%@for{}), do: Header.type(:amf_command)

    @impl true
    def serialize(%@for{command: command, transaction_id: transaction_id, args: args})
        when is_list(args) do
      Encoder.encode([command, transaction_id | args])
    end

    @impl true
    def serialize(%@for{command: command, transaction_id: transaction_id, args: args})
        when is_map(args) do
      Encoder.encode([command, transaction_id, args])
    end
  end
end
