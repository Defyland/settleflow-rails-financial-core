require "test_helper"

class OutboxPublishJobTest < ActiveJob::TestCase
  test "marks pending outbox events as published" do
    organization = create_organization
    wallet = create_wallet(organization:)
    event = OutboxEvents::Emit.call(
      organization:,
      aggregate: wallet,
      event_type: "wallet.created",
      payload: { wallet_id: wallet.public_id }
    )

    OutboxPublishJob.perform_now(event.id)

    assert event.reload.published?
    assert_equal 1, event.attempts
    assert event.published_at.present?
  end

  test "keeps transient failures pending with a scheduled retry" do
    organization = create_organization
    wallet = create_wallet(organization:)
    event = OutboxEvents::Emit.call(
      organization:,
      aggregate: wallet,
      event_type: "wallet.created",
      payload: { wallet_id: wallet.public_id }
    )

    failing_event = event
    def failing_event.publish!
      raise StandardError, "publisher down"
    end

    with_outbox_find_stub(failing_event) do
      OutboxPublishJob.perform_now(event.id)
    end

    event.reload
    assert event.pending?
    assert_equal 1, event.attempts
    assert event.next_attempt_at.present?
    assert_equal "StandardError", event.error_class
    assert_includes enqueued_jobs.map { |job| job[:job] }, OutboxPublishJob
  end

  test "dead letters after the retry budget is exhausted" do
    organization = create_organization
    wallet = create_wallet(organization:)
    event = OutboxEvents::Emit.call(
      organization:,
      aggregate: wallet,
      event_type: "wallet.created",
      payload: { wallet_id: wallet.public_id }
    )
    event.update!(attempts: OutboxEvent::MAX_ATTEMPTS - 1)

    failing_event = event
    def failing_event.publish!
      raise StandardError, "publisher down"
    end

    with_outbox_find_stub(failing_event) do
      OutboxPublishJob.perform_now(event.id)
    end

    event.reload
    assert event.dead_lettered?
    assert event.dead_lettered_at.present?
    assert_equal "StandardError", event.error_class
  end

  private

  def with_outbox_find_stub(record)
    original_find = OutboxEvent.method(:find)
    OutboxEvent.define_singleton_method(:find) { |_| record }
    yield
  ensure
    OutboxEvent.define_singleton_method(:find) { |*args, **kwargs, &block| original_find.call(*args, **kwargs, &block) }
  end
end
