require "rails_helper"

RSpec.describe Organization do
  it "authenticates active organizations by API key digest" do
    organization = create(:organization, api_key: "secret-key")

    expect(described_class.authenticate_api_key("secret-key")).to eq(organization)
    expect(described_class.authenticate_api_key("wrong-key")).to be_nil
  end

  it "does not authenticate suspended organizations" do
    create(:organization, api_key: "secret-key", status: "suspended")

    expect(described_class.authenticate_api_key("secret-key")).to be_nil
  end
end
