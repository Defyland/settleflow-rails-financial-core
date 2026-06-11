class CustomerSerializer
  def self.render(customer)
    {
      id: customer.public_id,
      external_id: customer.external_id,
      legal_name: ::Privacy::Redactor.name(customer.legal_name),
      document_kind: customer.document_kind,
      document_number: ::Privacy::Redactor.document(customer.document_number),
      status: customer.status,
      metadata: ::Privacy::Redactor.metadata(customer.metadata),
      created_at: customer.created_at.iso8601
    }
  end
end
