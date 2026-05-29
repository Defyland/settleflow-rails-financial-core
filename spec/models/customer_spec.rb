require "rails_helper"

RSpec.describe Customer do
  subject(:customer) { build(:customer) }

  it { is_expected.to validate_presence_of(:external_id) }
  it { is_expected.to validate_presence_of(:legal_name) }
  it { is_expected.to validate_inclusion_of(:document_kind).in_array(%w[cpf cnpj tax_id]) }
end
