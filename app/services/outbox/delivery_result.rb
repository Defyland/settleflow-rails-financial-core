module Outbox
  DeliveryResult = Data.define(:adapter, :destination, :message_id)
end
