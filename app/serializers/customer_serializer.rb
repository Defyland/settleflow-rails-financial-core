class CustomerSerializer
  def self.render(customer)
    {
      id: customer.public_id,
      external_id: customer.external_id,
      legal_name: customer.legal_name,
      document_kind: customer.document_kind,
      document_number: customer.document_number,
      status: customer.status,
      metadata: customer.metadata,
      created_at: customer.created_at.iso8601
    }
  end
end
