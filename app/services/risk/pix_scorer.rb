module Risk
  class PixScorer
    def self.call(amount_cents:, pix_key:, metadata: {})
      new(amount_cents:, pix_key:, metadata:).call
    end

    def initialize(amount_cents:, pix_key:, metadata: {})
      @amount_cents = amount_cents.to_i
      @pix_key = pix_key.to_s
      @metadata = metadata || {}
    end

    def call
      score = 10
      score += 65 if amount_cents >= 500_000
      score += 35 if pix_key.match?(/blocked|fraud|chargeback/i)
      score += 15 if metadata.fetch("new_device", false)
      [ score, 100 ].min
    end

    private

    attr_reader :amount_cents, :pix_key, :metadata
  end
end
