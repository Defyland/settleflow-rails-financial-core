module ApplicationHelper
  def money_cents(amount_cents, currency = "BRL")
    number_to_currency(amount_cents.to_i / 100.0, unit: "#{currency} ", separator: ",", delimiter: ".")
  end

  def compact_id(record)
    record.public_id.to_s.first(8)
  end

  def status_badge(status)
    tag.span(status.to_s.humanize, class: "status status--#{status}")
  end
end
