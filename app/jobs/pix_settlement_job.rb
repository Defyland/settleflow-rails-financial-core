class PixSettlementJob < ApplicationJob
  queue_as :settlement

  discard_on ActiveRecord::RecordNotFound

  def perform(pix_payment_id)
    pix_payment = PixPayment.find(pix_payment_id)
    return unless pix_payment.approved?

    PixPayments::Settle.call(
      organization: pix_payment.organization,
      pix_payment:,
      correlation_id: pix_payment.correlation_id
    )
  end
end
