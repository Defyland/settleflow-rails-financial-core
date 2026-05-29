module Idempotency
  Response = Data.define(:status, :body, :replayed)
end
