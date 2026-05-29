require "rails_helper"

RSpec.describe OutboxPublishJob do
  it "marks pending outbox events as published" do
    organization = create(:organization)
    wallet = create(:wallet, organization:)
    event = OutboxEvents::Emit.call(
      organization:,
      aggregate: wallet,
      event_type: "wallet.created",
      payload: { wallet_id: wallet.public_id }
    )

    described_class.perform_now(event.id)

    expect(event.reload).to be_published
    expect(event.attempts).to eq(1)
    expect(event.published_at).to be_present
  end
end
