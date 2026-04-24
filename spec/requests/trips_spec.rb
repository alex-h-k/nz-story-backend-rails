require "rails_helper"

RSpec.describe "Trips API", type: :request do
  def tomorrow = Date.tomorrow.to_s

  VALID_TRIP = {
    departureDate:       nil,          # filled in via let
    groupType:           "friends",
    groupSize:           "3",
    groupingPref:        "join_group",
    groupIdentity:       nil,
    companionPref:       "any",
    routeMode:           "preset",
    selectedRoute:       "alpine",
    ageGroup:            "26-35",
    preferredAgeGroup:   "any",
    preferredTotalSize:  "8",
    budget:              "mid",
    contactType:         "self",
    wechatId:            "alice_wx",
    notes:               ""
  }.freeze

  def valid_trip
    VALID_TRIP.merge(departureDate: tomorrow)
  end

  def post_trip(body:, openid: nil)
    headers = { "Content-Type" => "application/json" }
    headers["X-Wechat-Openid"] = openid if openid
    post "/api/v1/trips", params: { trip: body }.to_json, headers: headers
  end

  def get_trip(id, openid: nil)
    headers = { "Content-Type" => "application/json" }
    headers["X-Wechat-Openid"] = openid if openid
    get "/api/v1/trips/#{id}", headers: headers
  end

  # ── POST /api/v1/trips ────────────────────────────────────────────────────────

  describe "POST /api/v1/trips" do
    it "creates a trip request and returns 201 with id" do
      post_trip(body: valid_trip, openid: "user_openid_1")
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["id"]).to be > 0
      expect(body["status"]).to eq "waiting"
    end

    it "persists the trip to the database" do
      post_trip(body: valid_trip, openid: "user_openid_2")
      trip = TripRequest.find(JSON.parse(response.body)["id"])
      expect(trip.departure_date).to eq tomorrow
      expect(trip.wechat_id).to     eq "alice_wx"
      expect(trip.route_mode).to    eq "preset"
      expect(trip.selected_route).to eq "alpine"
      expect(trip.status).to eq "waiting"
    end

    it "auto-creates the user if the openid is new" do
      expect {
        post_trip(body: valid_trip, openid: "brand_new_openid")
      }.to change(User, :count).by(1)
      expect(User.find_by(openid: "brand_new_openid")).to be_present
    end

    it "returns 401 when the openid header is missing" do
      post_trip(body: valid_trip)
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 400 when departureDate is missing" do
      post_trip(body: valid_trip.merge(departureDate: nil), openid: "user_x")
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 400 when wechatId is missing" do
      post_trip(body: valid_trip.merge(wechatId: nil), openid: "user_x")
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 400 when groupingPref is missing" do
      post_trip(body: valid_trip.merge(groupingPref: nil), openid: "user_x")
      expect(response).to have_http_status(:bad_request)
    end

    it "triggers matching and pairs two compatible submissions" do
      perform_enqueued_jobs do
        post_trip(body: valid_trip.merge(wechatId: "alice_wx"), openid: "openid_alice")
        r1_id = JSON.parse(response.body)["id"]

        post_trip(body: valid_trip.merge(wechatId: "bob_wx"), openid: "openid_bob")

        expect(TripRequest.find(r1_id).status).to eq "matched"
        expect(TripRequest.last.status).to         eq "matched"
      end
    end
  end

  # ── GET /api/v1/trips/:id ─────────────────────────────────────────────────────

  describe "GET /api/v1/trips/:id" do
    it "returns trip status for the owner" do
      post_trip(body: valid_trip, openid: "owner_openid")
      trip_id = JSON.parse(response.body)["id"]

      get_trip(trip_id, openid: "owner_openid")
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq trip_id
      expect(body["status"]).to eq "waiting"
      expect(body["matchedWith"]).to be_nil
    end

    it "returns 403 when a different openid requests the trip" do
      post_trip(body: valid_trip, openid: "real_owner")
      trip_id = JSON.parse(response.body)["id"]

      get_trip(trip_id, openid: "someone_else")
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 404 for a non-existent trip id" do
      get_trip(99999, openid: "anyone")
      expect(response).to have_http_status(:not_found)
    end

    it "returns matchedWith wechatId after a successful match" do
      perform_enqueued_jobs do
        post_trip(body: valid_trip.merge(wechatId: "alice_wx"), openid: "openid_alice2")
        r1_id = JSON.parse(response.body)["id"]

        post_trip(body: valid_trip.merge(wechatId: "bob_wx"), openid: "openid_bob2")

        get_trip(r1_id, openid: "openid_alice2")
        body = JSON.parse(response.body)
        expect(body["status"]).to eq "matched"
        expect(body["matchedWith"]["wechatId"]).to eq "bob_wx"
      end
    end
  end

  # ── POST /api/v1/trips/match/run ──────────────────────────────────────────────

  describe "POST /api/v1/trips/match/run" do
    it "returns ok with a paired count" do
      post "/api/v1/trips/match/run"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["ok"]).to be true
      expect(body["paired"]).to be_a(Integer)
    end

    it "reports the correct pair count after seeding compatible requests" do
      post_trip(body: valid_trip.merge(wechatId: "wx1"), openid: "oid1")
      post_trip(body: valid_trip.merge(wechatId: "wx2"), openid: "oid2")

      # Reset both back to waiting to test /match/run explicitly
      TripRequest.update_all(status: "waiting", matched_with_id: nil, match_score: nil)

      post "/api/v1/trips/match/run"
      expect(JSON.parse(response.body)["paired"]).to eq 1
    end
  end
end
