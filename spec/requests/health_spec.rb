require "rails_helper"

RSpec.describe "GET /health", type: :request do
  it "returns 200 ok" do
    get "/health"
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["ok"]).to be true
  end
end
