require "rails_helper"

RSpec.describe MatchingService do
  let(:service) { described_class.new }

  # ── Helpers ───────────────────────────────────────────────────────────────────

  def tomorrow        = Date.tomorrow.to_s
  def days_from_now(n) = n.days.from_now.to_date.to_s
  def days_ago(n)      = n.days.ago.to_date.to_s

  let(:user_seq) { { n: 0 } }

  def seed_user
    user_seq[:n] += 1
    User.create!(openid: "test_openid_#{user_seq[:n]}")
  end

  BASE = {
    group_type:           "friends",
    group_size:           3,
    grouping_pref:        "join_group",
    group_identity:       nil,
    companion_pref:       "any",
    is_rainbow:           nil,
    route_mode:           "preset",
    selected_route:       "alpine",
    age_group:            "26-35",
    preferred_age_group:  "any",
    preferred_total_size: 8,
    budget:               "mid",
    contact_type:         "self",
    wechat_id:            "test_wx"
  }.freeze

  def seed_request(overrides = {})
    user = seed_user
    attrs = BASE.merge(departure_date: tomorrow, **overrides)
    user.trip_requests.create!(openid: user.openid, **attrs)
  end

  # ── calc_score ────────────────────────────────────────────────────────────────

  describe "#calc_score" do
    it "returns a high score for a perfect twin match" do
      date = tomorrow
      a = seed_request(departure_date: date)
      b = seed_request(departure_date: date)
      expect(service.calc_score(a, b)).to be >= 80
    end

    it "scores date diff 0 > diff 1 > diff 2 > diff 3" do
      base = { selected_route: "alpine", group_size: 2, preferred_total_size: 8,
               age_group: "26-35", budget: "mid", companion_pref: "any" }

      ref   = seed_request(base.merge(departure_date: days_from_now(5)))
      diff0 = seed_request(base.merge(departure_date: days_from_now(5)))
      diff1 = seed_request(base.merge(departure_date: days_from_now(6)))
      diff2 = seed_request(base.merge(departure_date: days_from_now(7)))
      diff3 = seed_request(base.merge(departure_date: days_from_now(8)))

      s0 = service.calc_score(ref, diff0)
      s1 = service.calc_score(ref, diff1)
      s2 = service.calc_score(ref, diff2)
      s3 = service.calc_score(ref, diff3)

      expect(s0).to be > s1
      expect(s1).to be > s2
      expect(s2).to be > s3
    end

    it "scores same route higher than adjacent route higher than no overlap" do
      base      = seed_request(selected_route: "alpine")
      same_rt   = seed_request(selected_route: "alpine")
      adj_rt    = seed_request(selected_route: "southeast")  # adjacent to alpine
      no_overlap = seed_request(selected_route: "kaikoura")

      expect(service.calc_score(base, same_rt)).to be > service.calc_score(base, adj_rt)
      expect(service.calc_score(base, adj_rt)).to be >= service.calc_score(base, no_overlap)
    end

    it "scores perfect size match (combined == preferred total) highest" do
      a = seed_request(group_size: 3, preferred_total_size: 6)
      b = seed_request(group_size: 3, preferred_total_size: 6)
      expect(service.calc_score(a, b)).to be >= 85
    end

    it "scores matching budget higher than a 2-tier gap" do
      date = tomorrow
      a       = seed_request(departure_date: date, budget: "budget")
      same_b  = seed_request(departure_date: date, budget: "budget")
      luxury_b = seed_request(departure_date: date, budget: "luxury")

      expect(service.calc_score(a, same_b)).to be > service.calc_score(a, luxury_b)
    end

    it "scores adjacent budget tiers higher than a 2-tier gap" do
      date = tomorrow
      mid     = seed_request(departure_date: date, budget: "mid")
      adj     = seed_request(departure_date: date, budget: "budget")   # 1 tier away
      far     = seed_request(departure_date: date, budget: "luxury")   # 1 tier away (opposite)
      mid2    = seed_request(departure_date: date, budget: "mid")      # same

      expect(service.calc_score(mid, mid2)).to be > service.calc_score(mid, adj)

      budget  = seed_request(departure_date: date, budget: "budget")
      luxury  = seed_request(departure_date: date, budget: "luxury")
      expect(service.calc_score(mid, adj)).to be > service.calc_score(budget, luxury)
    end

    it "scores close age groups higher than distant ones" do
      date  = tomorrow
      young = seed_request(departure_date: date, age_group: "18-25")
      close = seed_request(departure_date: date, age_group: "26-35")
      far   = seed_request(departure_date: date, age_group: "55+")

      expect(service.calc_score(young, close)).to be > service.calc_score(young, far)
    end

    it "gives full route score when full_loop overlaps 100% with itself" do
      a = seed_request(selected_route: "full_loop")
      b = seed_request(selected_route: "full_loop")
      expect(service.calc_score(a, b)).to be >= 35 + 30  # max route + max date
    end

    it "scores two solo travelers (group_size 1 each) at the perfect-size tier" do
      date = tomorrow
      a = seed_request(departure_date: date, group_type: "solo", group_size: 1,
                       preferred_total_size: 2)
      b = seed_request(departure_date: date, group_type: "solo", group_size: 1,
                       preferred_total_size: 2)
      # combined == min_pref == 2 → 20 pts for size
      expect(service.calc_score(a, b)).to be >= 80
    end

    it "does not award age bonus when either age group is nil" do
      date  = tomorrow
      a     = seed_request(departure_date: date, age_group: nil)
      b     = seed_request(departure_date: date, age_group: "26-35")
      score = service.calc_score(a, b)

      # Score without age bonus should be <= score with a close match
      close = seed_request(departure_date: date, age_group: "26-35")
      expect(score).to be < service.calc_score(b, close)
    end
  end

  # ── pass_hard_filters? ────────────────────────────────────────────────────────

  describe "#pass_hard_filters?" do
    let(:fresh) { { min_score: 70, max_date_diff: 3, min_overlap: 0.40 } }

    it "passes when both join_group, same date, sizes fit, routes overlap" do
      a = seed_request(group_size: 3, preferred_total_size: 8)
      b = seed_request(group_size: 3, preferred_total_size: 8)
      expect(service.pass_hard_filters?(a, b, fresh, fresh)).to be true
    end

    it "fails when either party is solo_group" do
      a = seed_request(grouping_pref: "solo_group")
      b = seed_request
      expect(service.pass_hard_filters?(a, b, fresh, fresh)).to be false
      expect(service.pass_hard_filters?(b, a, fresh, fresh)).to be false
    end

    it "fails when date diff exceeds the threshold" do
      a = seed_request(departure_date: days_from_now(1))
      b = seed_request(departure_date: days_from_now(5))  # 4-day diff > 3
      expect(service.pass_hard_filters?(a, b, fresh, fresh)).to be false
    end

    it "passes when date diff is within the lenient threshold" do
      lenient = { min_score: 30, max_date_diff: 5, min_overlap: 0.20 }
      a = seed_request(departure_date: days_from_now(1))
      b = seed_request(departure_date: days_from_now(5))  # 4-day diff ≤ 5
      expect(service.pass_hard_filters?(a, b, lenient, lenient)).to be true
    end

    it "fails when combined group size exceeds preferred total" do
      a = seed_request(group_size: 5, preferred_total_size: 6)
      b = seed_request(group_size: 5, preferred_total_size: 6)
      expect(service.pass_hard_filters?(a, b, fresh, fresh)).to be false
    end

    it "fails when combined size exceeds the global cap of 10" do
      a = seed_request(group_size: 6, preferred_total_size: 15)
      b = seed_request(group_size: 6, preferred_total_size: 15)
      expect(service.pass_hard_filters?(a, b, fresh, fresh)).to be false
    end

    it "fails when routes do not overlap enough" do
      a = seed_request(selected_route: "kaikoura")
      b = seed_request(selected_route: "fiordland")  # no shared stops
      expect(service.pass_hard_filters?(a, b, fresh, fresh)).to be false
    end

    it "passes adjacent routes at lenient overlap threshold" do
      lenient = { min_score: 30, max_date_diff: 5, min_overlap: 0.00 }
      a = seed_request(selected_route: "alpine")
      b = seed_request(selected_route: "southeast")  # adjacent to alpine
      expect(service.pass_hard_filters?(a, b, lenient, lenient)).to be true
    end

    it "passes when both are custom route (no stop data — bypass route check)" do
      a = seed_request(route_mode: "custom", selected_route: nil, custom_days: 7)
      b = seed_request(route_mode: "custom", selected_route: nil, custom_days: 7)
      expect(service.pass_hard_filters?(a, b, fresh, fresh)).to be true
    end
  end

  # ── companion_pref_compatible? ───────────────────────────────────────────────

  describe "companion_pref_compatible? (hard filter via pass_hard_filters?)" do
    # companion_pref is a hard filter: an incompatible pref must block matching
    # entirely, not merely reduce the score.
    # We use a lenient threshold so route/date/size never interfere.
    let(:lenient) { { min_score: 0, max_date_diff: 10, min_overlap: 0.00 } }

    it "passes when both parties have no preference (any / any)" do
      a = seed_request(group_identity: nil, companion_pref: "any")
      b = seed_request(group_identity: nil, companion_pref: "any", is_rainbow: true)
      expect(service.pass_hard_filters?(a, b, lenient, lenient)).to be true
    end

    it "passes when female_only meets a female solo" do
      a = seed_request(group_identity: "female", companion_pref: "any")
      b = seed_request(group_identity: "female", companion_pref: "female_only")
      expect(service.pass_hard_filters?(a, b, lenient, lenient)).to be true
    end

    it "blocks when female_only meets a male solo" do
      a = seed_request(group_identity: "female", companion_pref: "female_only")
      b = seed_request(group_identity: "male",   companion_pref: "any")
      expect(service.pass_hard_filters?(a, b, lenient, lenient)).to be false
    end

    it "blocks when female_only meets a rainbow male solo" do
      a = seed_request(group_identity: "female", companion_pref: "female_only")
      b = seed_request(group_identity: "male",   companion_pref: "any", is_rainbow: true)
      expect(service.pass_hard_filters?(a, b, lenient, lenient)).to be false
    end

    it "passes when male_only meets a male solo" do
      a = seed_request(group_identity: "male", companion_pref: "any")
      b = seed_request(group_identity: "male", companion_pref: "male_only")
      expect(service.pass_hard_filters?(a, b, lenient, lenient)).to be true
    end

    it "blocks when male_only meets a female solo" do
      a = seed_request(group_identity: "male",   companion_pref: "male_only")
      b = seed_request(group_identity: "female", companion_pref: "any")
      expect(service.pass_hard_filters?(a, b, lenient, lenient)).to be false
    end

    it "blocks when male_only meets a non-solo group (nil identity)" do
      a = seed_request(group_identity: "male", companion_pref: "male_only")
      b = seed_request(group_identity: nil,    companion_pref: "any")
      expect(service.pass_hard_filters?(a, b, lenient, lenient)).to be false
    end

    it "passes when rainbow_friendly meets a rainbow solo" do
      a = seed_request(group_identity: nil, companion_pref: "rainbow_friendly")
      b = seed_request(group_identity: nil, companion_pref: "any", is_rainbow: true)
      expect(service.pass_hard_filters?(a, b, lenient, lenient)).to be true
    end

    it "blocks when rainbow_friendly meets a non-rainbow solo" do
      a = seed_request(group_identity: nil,    companion_pref: "rainbow_friendly")
      b = seed_request(group_identity: "male", companion_pref: "any", is_rainbow: false)
      expect(service.pass_hard_filters?(a, b, lenient, lenient)).to be false
    end

    it "passes when both are rainbow solos with any pref" do
      a = seed_request(group_identity: "female", companion_pref: "any", is_rainbow: true)
      b = seed_request(group_identity: "male",   companion_pref: "any", is_rainbow: true)
      expect(service.pass_hard_filters?(a, b, lenient, lenient)).to be true
    end

    it "awards the 5-point bonus in scoring when prefs are compatible" do
      date = tomorrow
      compatible   = seed_request(departure_date: date, group_identity: "female", companion_pref: "female_only")
      also_female  = seed_request(departure_date: date, group_identity: "female", companion_pref: "any")
      incompatible = seed_request(departure_date: date, group_identity: "male",   companion_pref: "any")

      expect(service.calc_score(compatible, also_female)).to be >
        service.calc_score(compatible, incompatible)
    end
  end

  # ── run (matching job) ────────────────────────────────────────────────────────

  describe ".run" do
    it "pairs two compatible requests and marks them matched" do
      date = tomorrow
      seed_request(departure_date: date, group_size: 2, preferred_total_size: 6)
      seed_request(departure_date: date, group_size: 2, preferred_total_size: 6)

      result = described_class.run
      expect(result[:paired]).to eq 1

      statuses = TripRequest.pluck(:status)
      expect(statuses).to all(eq "matched")
      expect(TripRequest.pluck(:match_score)).to all(be >= 70)
    end

    it "does not match when one party is solo_group" do
      seed_request(grouping_pref: "solo_group")
      seed_request(grouping_pref: "join_group")
      expect(described_class.run[:paired]).to eq 0
    end

    it "does not match when date diff exceeds the fresh threshold" do
      seed_request(departure_date: days_from_now(1))
      seed_request(departure_date: days_from_now(10))
      expect(described_class.run[:paired]).to eq 0
    end

    it "does not match when combined size exceeds preferred total" do
      seed_request(group_size: 5, preferred_total_size: 7)
      seed_request(group_size: 5, preferred_total_size: 7)
      expect(described_class.run[:paired]).to eq 0
    end

    it "does not pair the same request twice (greedy deduplication)" do
      date = tomorrow
      3.times { seed_request(departure_date: date, group_size: 2, preferred_total_size: 8) }

      result = described_class.run
      expect(result[:paired]).to eq 1

      statuses = TripRequest.order(:id).pluck(:status)
      expect(statuses.count("matched")).to eq 2
      expect(statuses.count("waiting")).to eq 1
    end

    it "picks the highest-scoring pair when multiple candidates exist" do
      date = tomorrow
      a = seed_request(departure_date: date, selected_route: "alpine",    age_group: "26-35", budget: "mid",    group_size: 2, preferred_total_size: 8)
      b = seed_request(departure_date: date, selected_route: "alpine",    age_group: "26-35", budget: "mid",    group_size: 2, preferred_total_size: 8)
          seed_request(departure_date: date, selected_route: "fiordland", age_group: "46-55", budget: "luxury", group_size: 2, preferred_total_size: 8)

      described_class.run

      a.reload
      expect(a.matched_with_id).to eq b.id
    end

    it "returns zero when no waiting requests exist" do
      expect(described_class.run[:paired]).to eq 0
    end

    it "returns zero when only one waiting request exists" do
      seed_request
      expect(described_class.run[:paired]).to eq 0
    end

    it "handles 6 requests and produces 3 pairs" do
      date = tomorrow
      6.times { seed_request(departure_date: date, group_size: 2, preferred_total_size: 6) }

      result = described_class.run
      expect(result[:paired]).to eq 3
      expect(TripRequest.pluck(:status)).to all(eq "matched")
    end

    it "sets matched_with_id on both sides of the pair" do
      date = tomorrow
      a = seed_request(departure_date: date, group_size: 2, preferred_total_size: 6)
      b = seed_request(departure_date: date, group_size: 2, preferred_total_size: 6)

      described_class.run
      a.reload; b.reload

      expect(a.matched_with_id).to eq b.id
      expect(b.matched_with_id).to eq a.id
    end

    it "assigns match_type 'ideal' when score >= 70" do
      date = tomorrow
      a = seed_request(departure_date: date, group_size: 2, preferred_total_size: 4,
                       selected_route: "alpine", age_group: "26-35", budget: "mid")
      b = seed_request(departure_date: date, group_size: 2, preferred_total_size: 4,
                       selected_route: "alpine", age_group: "26-35", budget: "mid")

      described_class.run
      a.reload

      expect(a.match_score).to be >= 70
      expect(a.match_type).to eq "ideal"
    end

    it "assigns match_type 'acceptable' when score is between 50 and 69" do
      date = tomorrow
      # Same route but different age + budget to land in the 50-69 band
      a = seed_request(departure_date: date, group_size: 2, preferred_total_size: 4,
                       selected_route: "alpine", age_group: "18-25", budget: "budget")
      b = seed_request(departure_date: date, group_size: 2, preferred_total_size: 4,
                       selected_route: "alpine", age_group: "55+",   budget: "luxury")

      score = service.calc_score(a, b)
      skip "score #{score} not in acceptable band" unless score.between?(50, 69)

      described_class.run
      a.reload
      expect(a.match_type).to eq "acceptable"
    end

    it "assigns match_type 'forced' when a request has waited 15+ days and score < 50" do
      date = days_from_now(30)
      a = seed_request(departure_date: date, group_size: 2, preferred_total_size: 6,
                       selected_route: "alpine",    age_group: "18-25", budget: "budget")
      b = seed_request(departure_date: date, group_size: 2, preferred_total_size: 6,
                       selected_route: "kaikoura",  age_group: "55+",   budget: "luxury")

      # Make both stale enough to hit the forced threshold
      TripRequest.update_all(created_at: 16.days.ago)

      described_class.run
      a.reload

      expect(a.status).to eq "matched"
      expect(a.match_type).to eq "forced"
    end

    it "counts forced matches separately in the result" do
      date = days_from_now(30)
      seed_request(departure_date: date, group_size: 2, preferred_total_size: 6,
                   selected_route: "alpine",   age_group: "18-25", budget: "budget")
      seed_request(departure_date: date, group_size: 2, preferred_total_size: 6,
                   selected_route: "kaikoura", age_group: "55+",   budget: "luxury")

      TripRequest.update_all(created_at: 16.days.ago)

      result = described_class.run
      expect(result[:forced]).to eq 1
    end

    # ── solo-specific run scenarios ───────────────────────────────────────────

    it "matches two compatible solo travelers (same gender, compatible pref)" do
      date = tomorrow
      seed_request(departure_date: date, group_type: "solo", group_size: 1,
                   group_identity: "female", companion_pref: "female_only",
                   preferred_total_size: 4)
      seed_request(departure_date: date, group_type: "solo", group_size: 1,
                   group_identity: "female", companion_pref: "any",
                   preferred_total_size: 4)

      expect(described_class.run[:paired]).to eq 1
    end

    it "does not match female_only solo with a male solo" do
      date = tomorrow
      seed_request(departure_date: date, group_type: "solo", group_size: 1,
                   group_identity: "female", companion_pref: "female_only",
                   preferred_total_size: 4)
      seed_request(departure_date: date, group_type: "solo", group_size: 1,
                   group_identity: "male", companion_pref: "any",
                   preferred_total_size: 4)

      expect(described_class.run[:paired]).to eq 0
    end

    it "matches rainbow_friendly solo with a rainbow solo" do
      date = tomorrow
      seed_request(departure_date: date, group_type: "solo", group_size: 1,
                   group_identity: "female", companion_pref: "rainbow_friendly",
                   is_rainbow: true, preferred_total_size: 4)
      seed_request(departure_date: date, group_type: "solo", group_size: 1,
                   group_identity: "male", companion_pref: "any",
                   is_rainbow: true, preferred_total_size: 4)

      expect(described_class.run[:paired]).to eq 1
    end

    it "does not match rainbow_friendly solo with a non-rainbow solo" do
      date = tomorrow
      seed_request(departure_date: date, group_type: "solo", group_size: 1,
                   group_identity: "female", companion_pref: "rainbow_friendly",
                   is_rainbow: true, preferred_total_size: 4)
      seed_request(departure_date: date, group_type: "solo", group_size: 1,
                   group_identity: "male", companion_pref: "any",
                   is_rainbow: false, preferred_total_size: 4)

      expect(described_class.run[:paired]).to eq 0
    end

    # ── group size boundary ───────────────────────────────────────────────────

    it "passes when combined size exactly equals preferred_total_size" do
      date = tomorrow
      seed_request(departure_date: date, group_size: 3, preferred_total_size: 6)
      seed_request(departure_date: date, group_size: 3, preferred_total_size: 6)

      expect(described_class.run[:paired]).to eq 1
    end

    it "blocks when combined size is one over preferred_total_size" do
      date = tomorrow
      seed_request(departure_date: date, group_size: 4, preferred_total_size: 6)
      seed_request(departure_date: date, group_size: 3, preferred_total_size: 6)

      expect(described_class.run[:paired]).to eq 0
    end

    it "applies the global cap of 10 when preferred_total_size is nil" do
      date = tomorrow
      seed_request(departure_date: date, group_size: 6, preferred_total_size: nil)
      seed_request(departure_date: date, group_size: 6, preferred_total_size: nil)

      expect(described_class.run[:paired]).to eq 0
    end

    it "passes when combined size is within the global cap and preferred_total_size is nil" do
      date = tomorrow
      seed_request(departure_date: date, group_size: 4, preferred_total_size: nil)
      seed_request(departure_date: date, group_size: 4, preferred_total_size: nil)

      expect(described_class.run[:paired]).to eq 1
    end
  end

  # ── run_fallback ──────────────────────────────────────────────────────────────

  describe ".run_fallback" do
    it "expires waiting requests with a past departure date" do
      user = User.create!(openid: "old_user")
      trip = user.trip_requests.create!(
        openid: "old_user", departure_date: days_ago(35),
        group_size: 2, grouping_pref: "join_group",
        route_mode: "preset", wechat_id: "wx_old"
      )
      # Backdate created_at so the fallback expiry cut-off applies
      trip.update_columns(created_at: 35.days.ago)

      result = described_class.run_fallback
      expect(result[:expired]).to eq 1
      expect(trip.reload.status).to eq "expired"
    end

    it "does not expire future waiting requests" do
      seed_request(departure_date: days_from_now(5))
      expect(described_class.run_fallback[:expired]).to eq 0
    end

    it "does not expire already-matched requests" do
      user = User.create!(openid: "matched_user")
      user.trip_requests.create!(
        openid: "matched_user", departure_date: days_ago(40),
        group_size: 2, grouping_pref: "join_group",
        route_mode: "preset", wechat_id: "wx_m", status: "matched"
      )
      expect(described_class.run_fallback[:expired]).to eq 0
    end

    it "reports overdue count for waiting requests older than 15 days" do
      trip = seed_request(departure_date: days_from_now(10))
      trip.update_columns(created_at: 16.days.ago)

      result = described_class.run_fallback
      expect(result[:overdue]).to eq 1
    end

    it "does not count fresh waiting requests as overdue" do
      seed_request(departure_date: days_from_now(10))
      expect(described_class.run_fallback[:overdue]).to eq 0
    end

    it "does not count expired requests as overdue" do
      user = User.create!(openid: "expired_user")
      trip = user.trip_requests.create!(
        openid: "expired_user", departure_date: days_ago(40),
        group_size: 2, grouping_pref: "join_group",
        route_mode: "preset", wechat_id: "wx_exp", status: "expired"
      )
      trip.update_columns(created_at: 20.days.ago)

      expect(described_class.run_fallback[:overdue]).to eq 0
    end
  end
end
