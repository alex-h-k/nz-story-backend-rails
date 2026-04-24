require "rails_helper"

RSpec.describe "POST /api/v1/auth/wechat", type: :request do
  def wechat_auth(body)
    post "/api/v1/auth/wechat", params: body.to_json,
      headers: { "Content-Type" => "application/json" }
  end

  it "returns an openid for a valid code" do
    wechat_auth(code: "wx_test_code_abc123")
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["openid"]).to be_a(String).and be_present
  end

  it "creates a user row in the database" do
    expect { wechat_auth(code: "code_xyz") }.to change(User, :count).by(1)
  end

  it "is idempotent — calling twice with the same code does not create duplicate users" do
    wechat_auth(code: "same_code")
    expect { wechat_auth(code: "same_code") }.not_to change(User, :count)
  end

  it "returns 400 when code is missing" do
    wechat_auth({})
    expect(response).to have_http_status(:bad_request)
  end
end
