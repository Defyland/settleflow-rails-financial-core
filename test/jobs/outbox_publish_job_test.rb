require "test_helper"

class OutboxPublishJobTest < ActiveJob::TestCase
  teardown do
    Rails.application.config.x.outbox.publisher = nil
  end

  test "publishes through the configured adapter before marking events as published" do
    publisher = RecordingOutboxPublisher.new
    Rails.application.config.x.outbox.publisher = publisher
    event = create_pending_funding_event

    OutboxPublishJob.perform_now(event.id)

    assert_equal 1, publisher.envelopes.size
    assert_equal event.public_id, publisher.envelopes.first.fetch(:id)
    assert_equal "wallet.funded", publisher.envelopes.first.fetch(:event_type)
    assert event.reload.published?
    assert_equal 1, event.attempts
    assert event.published_at.present?
    assert_equal "test", event.publisher
    assert_equal "memory://outbox", event.published_to
    assert_equal "msg-#{event.public_id}", event.publisher_message_id
  end

  test "enqueues ClickHouse sync after publishing when analytics is configured" do
    Rails.application.config.x.outbox.publisher = RecordingOutboxPublisher.new
    event = create_pending_funding_event
    clear_enqueued_jobs

    original_configured = Analytics::ClickHouseClient.method(:configured?)
    Analytics::ClickHouseClient.define_singleton_method(:configured?) { true }
    OutboxPublishJob.perform_now(event.id)

    assert event.reload.published?
    assert_includes enqueued_jobs.map { |job| job[:job] }, ClickHouseSyncJob
  ensure
    Analytics::ClickHouseClient.define_singleton_method(:configured?) { original_configured.call } if original_configured
  end

  test "does not mark published events as failed when analytics enqueue fails" do
    Rails.application.config.x.outbox.publisher = RecordingOutboxPublisher.new
    event = create_pending_funding_event
    clear_enqueued_jobs

    original_configured = Analytics::ClickHouseClient.method(:configured?)
    original_perform_later = ClickHouseSyncJob.method(:perform_later)
    Analytics::ClickHouseClient.define_singleton_method(:configured?) { true }
    ClickHouseSyncJob.define_singleton_method(:perform_later) { |*args, **kwargs| raise "analytics queue unavailable" }

    OutboxPublishJob.perform_now(event.id)

    event.reload
    assert event.published?
    assert_equal 1, event.attempts
    assert_nil event.last_error
    assert_nil event.error_class
    assert_empty enqueued_jobs.select { |job| job[:job] == OutboxPublishJob }
  ensure
    Analytics::ClickHouseClient.define_singleton_method(:configured?) { original_configured.call } if original_configured
    ClickHouseSyncJob.define_singleton_method(:perform_later) do |*args, **kwargs, &block|
      original_perform_later.call(*args, **kwargs, &block)
    end
  end

  test "keeps transient failures pending with a scheduled retry" do
    Rails.application.config.x.outbox.publisher = FailingOutboxPublisher.new
    event = create_pending_funding_event
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
    publisher = RecordingOutboxPublisher.new
    Rails.application.config.x.outbox.publisher = publisher
    event = create_pending_funding_event
    event.update!(status: "publishing", last_attempted_at: Time.current)

    OutboxPublishJob.perform_now(event.id)

    assert_empty publisher.envelopes
    assert event.reload.publishing?
    assert_equal 0, event.attempts
  end

  test "reclaims stale publishing events" do
    publisher = RecordingOutboxPublisher.new
    Rails.application.config.x.outbox.publisher = publisher
    event = create_pending_funding_event
    event.update!(status: "publishing", last_attempted_at: 30.minutes.ago)

    OutboxPublishJob.perform_now(event.id)

    assert_equal 1, publisher.envelopes.size
    assert event.reload.published?
    assert_equal 1, event.attempts
  end

  test "dead letters after the retry budget is exhausted" do
    Rails.application.config.x.outbox.publisher = FailingOutboxPublisher.new
    event = create_pending_funding_event
    event.update!(attempts: OutboxEvent::MAX_ATTEMPTS - 1)
    clear_enqueued_jobs

    OutboxPublishJob.perform_now(event.id)

    event.reload
    assert event.dead_lettered?
    assert event.dead_lettered_at.present?
    assert_equal "StandardError", event.error_class
  end

  private

  def create_pending_funding_event
    organization = create_organization
    wallet = create_wallet(organization:)
    funding = fund_wallet(
      organization:,
      wallet:,
      external_id: "outbox-publish-funding-#{SecureRandom.hex(4)}",
      amount_cents: 100
    )
    organization.outbox_events.find_by!(
      aggregate_type: "Funding",
      aggregate_id: funding.id,
      event_type: "wallet.funded"
    )
  end

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
