require "test_helper"

class OutboxPublishJobTest < ActiveJob::TestCase
  teardown do
    Rails.application.config.x.outbox.publisher = nil
  end

  test "publishes through the configured adapter before marking events as published" do
    organization = create_organization
    wallet = create_wallet(organization:)
    publisher = RecordingOutboxPublisher.new
    Rails.application.config.x.outbox.publisher = publisher
    event = OutboxEvents::Emit.call(
      organization:,
      aggregate: wallet,
      event_type: "wallet.created",
      payload: { wallet_id: wallet.public_id }
    )

    OutboxPublishJob.perform_now(event.id)

    assert_equal 1, publisher.envelopes.size
    assert_equal event.public_id, publisher.envelopes.first.fetch(:id)
    assert_equal "wallet.created", publisher.envelopes.first.fetch(:event_type)
    assert event.reload.published?
    assert_equal 1, event.attempts
    assert event.published_at.present?
    assert_equal "test", event.publisher
    assert_equal "memory://outbox", event.published_to
    assert_equal "msg-#{event.public_id}", event.publisher_message_id
  end

  test "keeps transient failures pending with a scheduled retry" do
    organization = create_organization
    wallet = create_wallet(organization:)
    Rails.application.config.x.outbox.publisher = FailingOutboxPublisher.new
    event = OutboxEvents::Emit.call(
      organization:,
      aggregate: wallet,
      event_type: "wallet.created",
      payload: { wallet_id: wallet.public_id }
    )
    clear_enqueued_jobs

    OutboxPublishJob.perform_now(event.id)

    event.reload
    assert event.pending?
    assert_equal 1, event.attempts
    assert event.next_attempt_at.present?
    assert_equal "StandardError", event.error_class
    assert_includes enqueued_jobs.map { |job| job[:job] }, OutboxPublishJob
  end

  test "does not publish an event currently claimed by another worker" do
    organization = create_organization
    wallet = create_wallet(organization:)
    publisher = RecordingOutboxPublisher.new
    Rails.application.config.x.outbox.publisher = publisher
    event = OutboxEvents::Emit.call(
      organization:,
      aggregate: wallet,
      event_type: "wallet.created",
      payload: { wallet_id: wallet.public_id }
    )
    event.update!(status: "publishing", last_attempted_at: Time.current)

    OutboxPublishJob.perform_now(event.id)

    assert_empty publisher.envelopes
    assert event.reload.publishing?
    assert_equal 0, event.attempts
  end

  test "reclaims stale publishing events" do
    organization = create_organization
    wallet = create_wallet(organization:)
    publisher = RecordingOutboxPublisher.new
    Rails.application.config.x.outbox.publisher = publisher
    event = OutboxEvents::Emit.call(
      organization:,
      aggregate: wallet,
      event_type: "wallet.created",
      payload: { wallet_id: wallet.public_id }
    )
    event.update!(status: "publishing", last_attempted_at: 30.minutes.ago)

    OutboxPublishJob.perform_now(event.id)

    assert_equal 1, publisher.envelopes.size
    assert event.reload.published?
    assert_equal 1, event.attempts
  end

  test "dead letters after the retry budget is exhausted" do
    organization = create_organization
    wallet = create_wallet(organization:)
    Rails.application.config.x.outbox.publisher = FailingOutboxPublisher.new
    event = OutboxEvents::Emit.call(
      organization:,
      aggregate: wallet,
      event_type: "wallet.created",
      payload: { wallet_id: wallet.public_id }
    )
    event.update!(attempts: OutboxEvent::MAX_ATTEMPTS - 1)
    clear_enqueued_jobs

    OutboxPublishJob.perform_now(event.id)

    event.reload
    assert event.dead_lettered?
    assert event.dead_lettered_at.present?
    assert_equal "StandardError", event.error_class
  end

  private

  class RecordingOutboxPublisher
    attr_reader :envelopes

    def initialize
      @envelopes = []
    end

    def publish(envelope)
      envelopes << envelope
      Outbox::DeliveryResult.new(
        adapter: "test",
        destination: "memory://outbox",
        message_id: "msg-#{envelope.fetch(:id)}"
      )
    end
  end

  class FailingOutboxPublisher
    def publish(_envelope)
      raise StandardError, "publisher down"
    end
  end
end
