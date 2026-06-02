require "test_helper"
require "timeout"

class FinancialConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "settles a Pix payment once under concurrent workers" do
    organization, wallet = funded_wallet("pix-settlement-concurrency")
    pix_payment = create_pix_payment(
      organization:,
      wallet:,
      external_id: "pix-settlement-concurrency",
      pix_key: "pix-settlement-concurrency@example.com",
      amount_cents: 3_000
    )

    results = run_concurrently do
      PixPayments::Settle.call(organization:, pix_payment: PixPayment.find(pix_payment.id))
    end

    assert_single_success(results)
    assert pix_payment.reload.settled?
    assert_equal 1, organization.journal_entries.where(reference: pix_payment, event_type: "pix.payment.settled").count
  end

  test "settles a payout once under concurrent workers" do
    organization, wallet = funded_wallet("payout-concurrency")
    payout = Payouts::Create.call(
      organization:,
      wallet:,
      external_id: "payout-concurrency",
      amount_cents: 4_000,
      settlement_delay_days: 0,
      destination_reference: "bank-account-concurrency",
      idempotency_key: "payout-concurrency"
    )

    results = run_concurrently do
      Payouts::Settle.call(organization:, payout: Payout.find(payout.id))
    end

    assert_single_success(results)
    assert payout.reload.settled?
    assert_equal 1, organization.journal_entries.where(reference: payout, event_type: "payout.settled").count
  end

  test "prevents concurrent refunds from exceeding Pix amount" do
    organization, wallet = funded_wallet("refund-concurrency", amount_cents: 20_000)
    pix_payment = create_pix_payment(
      organization:,
      wallet:,
      external_id: "refund-concurrency-pix",
      pix_key: "refund-concurrency@example.com",
      amount_cents: 5_000
    )
    PixPayments::Settle.call(organization:, pix_payment:)

    results = run_concurrently do |index|
      Refunds::Create.call(
        organization:,
        pix_payment: PixPayment.find(pix_payment.id),
        external_id: "refund-concurrency-#{index}",
        amount_cents: 3_000,
        reason: "concurrent_refund",
        idempotency_key: "refund-concurrency-#{index}"
      )
    end

    assert_single_success(results)
    assert_equal 1, organization.refunds.where(pix_payment:).count
    assert_equal 18_000, wallet.balance_projection.reload.available_cents
  end

  test "accepts a MED case once under concurrent workers" do
    organization, wallet = funded_wallet("med-concurrency", amount_cents: 20_000)
    pix_payment = create_pix_payment(
      organization:,
      wallet:,
      external_id: "med-concurrency-pix",
      pix_key: "med-concurrency@example.com",
      amount_cents: 5_000
    )
    PixPayments::Settle.call(organization:, pix_payment:)
    med_case = MedCases::Open.call(
      organization:,
      pix_payment:,
      external_id: "med-concurrency",
      amount_cents: 3_000,
      reason: "fraud_report",
      idempotency_key: "med-concurrency"
    )

    results = run_concurrently do
      MedCases::Accept.call(organization:, med_case: MedCase.find(med_case.id))
    end

    assert_single_success(results)
    assert med_case.reload.refunded?
    assert_equal 1, organization.refunds.where(idempotency_key: "med_case.refund:#{med_case.id}").count
  end

  private

  def funded_wallet(prefix, amount_cents: 10_000)
    organization = create_organization
    wallet = create_wallet(organization:, external_id: "#{prefix}-wallet")
    fund_wallet(organization:, wallet:, external_id: "#{prefix}-funding", amount_cents:)
    [ organization, wallet ]
  end

  def run_concurrently(worker_count = 2)
    ready = Queue.new
    start = Queue.new
    results = Queue.new
    threads = worker_count.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          results << [ :ok, yield(index) ]
        rescue StandardError => e
          results << [ :error, e.class.name, e.message ]
        end
      end
    end

    Timeout.timeout(10) do
      worker_count.times { ready.pop }
      worker_count.times { start << true }
      threads.each(&:join)
      worker_count.times.map { results.pop }
    end
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
    ActiveRecord::Base.connection_handler.clear_active_connections!
  end

  def assert_single_success(results)
    assert_equal 1, results.count { |result| result.first == :ok }, results.inspect
    assert_equal 1, results.count { |result| result.first == :error }, results.inspect
  end
end
