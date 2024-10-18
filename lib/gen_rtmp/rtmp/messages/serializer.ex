defprotocol GenRtmp.Rtmp.Messages.Serializer do
  def message_type_id(message)
  def serialize(message)
end
