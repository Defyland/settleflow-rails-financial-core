require "test_helper"

class OutboxSweepJobTest < ActiveJob::TestCase
  setup do
    OutboxEvent.pending.update_all(next_attempt_at: 1.year.from_now)
    OutboxEvent.publishing.update_all(last_attempted_at: Time.current)
    clear_enqueued_jobs
  end

  test "enqueues publish jobs for pending due and stale publishing events" do
    pending_due = create_pending_funding_event
    stale_publishing = create_pending_funding_event
    stale_publishing.update!(status: "publishing", last_attempted_at: 30.minutes.ago)
    clear_enqueued_jobs

    OutboxSweepJob.perform_now(batch_size: 10)

    assert_equal 2, enqueued_jobs.count { |job| job[:job] == OutboxPublishJob }
    assert_enqueued_with(job: OutboxPublishJob, args: [ pending_due.id ])
    assert_enqueued_with(job: OutboxPublishJob, args: [ stale_publishing.id ])
  end

  test "does not enqueue non-due or actively claimed events" do
    pending_future = create_pending_funding_event
    pending_future.update!(next_attempt_at: 10.minutes.from_now)
    active_publishing = create_pending_funding_event
    active_publishing.update!(status: "publishing", last_attempted_at: Time.current)
    clear_enqueued_jobs

    OutboxSweepJob.perform_now(batch_size: 10)

    assert_empty enqueued_jobs.select { |job| job[:job] == OutboxPublishJob }
  end

  private

  def create_pending_funding_event
    organization = create_organization
    wallet = create_wallet(organization:)
    funding = fund_wallet(
      organization:,
      wallet:,
      external_id: "outbox-sweep-funding-#{SecureRandom.hex(4)}",
      amount_cents: 100
    )
    organization.outbox_events.find_by!(
      aggregate_type: "Funding",
      aggregate_id: funding.id,
      event_type: "wallet.funded"
    )
  end
end
