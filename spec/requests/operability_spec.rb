require "rails_helper"

RSpec.describe "Operability endpoints", type: :request do
  it "serves readiness without authentication" do
    get "/ready"

    expect(response).to have_http_status(:ok)
    expect(json_body.fetch("status")).to eq("ready")
  end

  it "serves Prometheus metrics without authentication" do
    get "/metrics"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("settleflow_http_requests_total")
  end
end
