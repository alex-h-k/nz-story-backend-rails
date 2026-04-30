def make_user(openid)
  User.find_or_create_by!(openid: openid)
end

def make_trip(user, overrides = {})
  defaults = {
    openid:              user.openid,
    departure_date:      7.days.from_now.to_date.to_s,
    group_type:          "friends",
    group_size:          2,
    grouping_pref:       "join_group",
    group_identity:      nil,
    companion_pref:      "any",
    is_rainbow:          nil,
    route_mode:          "preset",
    selected_route:      "alpine",
    age_group:           "26-35",
    preferred_age_group: "any",
    preferred_total_size: 6,
    budget:              "mid",
    contact_type:        "self",
    wechat_id:           user.openid,
    status:              "waiting"
  }
  user.trip_requests.create!(defaults.merge(overrides))
end

# ── Scenario 1: ideal solo pair ───────────────────────────────────────────────
# Two solo female travelers on the same route, same date, rainbow-friendly pref.
# Expected: high-score ideal match.

alice = make_user("alice_openid")
bob   = make_user("bob_openid")

make_trip(alice,
  group_type:       "solo",
  group_size:       1,
  group_identity:   "female",
  companion_pref:   "female_only",
  is_rainbow:       false,
  selected_route:   "alpine",
  age_group:        "26-35",
  preferred_total_size: 4,
  budget:           "mid",
  wechat_id:        "alice_wx")

make_trip(bob,
  group_type:       "solo",
  group_size:       1,
  group_identity:   "female",
  companion_pref:   "any",
  is_rainbow:       false,
  selected_route:   "alpine",
  age_group:        "26-35",
  preferred_total_size: 4,
  budget:           "mid",
  wechat_id:        "bob_wx")

# ── Scenario 2: male solo pair ────────────────────────────────────────────────
# Two solo male travelers. One wants male-only company.

charlie = make_user("charlie_openid")
dan     = make_user("dan_openid")

make_trip(charlie,
  group_type:       "solo",
  group_size:       1,
  group_identity:   "male",
  companion_pref:   "male_only",
  is_rainbow:       false,
  selected_route:   "fiordland",
  age_group:        "36-45",
  preferred_total_size: 4,
  budget:           "budget",
  wechat_id:        "charlie_wx")

make_trip(dan,
  group_type:       "solo",
  group_size:       1,
  group_identity:   "male",
  companion_pref:   "any",
  is_rainbow:       false,
  selected_route:   "fiordland",
  age_group:        "36-45",
  preferred_total_size: 4,
  budget:           "budget",
  wechat_id:        "dan_wx")

# ── Scenario 3: rainbow-friendly pair ────────────────────────────────────────
# One traveler wants rainbow-friendly company; the other is openly rainbow.

eve  = make_user("eve_openid")
finn = make_user("finn_openid")

make_trip(eve,
  group_type:       "solo",
  group_size:       1,
  group_identity:   "female",
  companion_pref:   "rainbow_friendly",
  is_rainbow:       true,
  selected_route:   "southeast",
  age_group:        "18-25",
  preferred_total_size: 4,
  budget:           "budget",
  wechat_id:        "eve_wx")

make_trip(finn,
  group_type:       "solo",
  group_size:       1,
  group_identity:   "male",
  companion_pref:   "any",
  is_rainbow:       true,
  selected_route:   "southeast",
  age_group:        "18-25",
  preferred_total_size: 4,
  budget:           "budget",
  wechat_id:        "finn_wx")

# ── Scenario 4: friends group joining another group ───────────────────────────
# Two friend groups on the same route want to merge into a larger group.

grace = make_user("grace_openid")
henry = make_user("henry_openid")

make_trip(grace,
  group_type:       "friends",
  group_size:       3,
  group_identity:   nil,
  companion_pref:   "any",
  selected_route:   "full_loop",
  age_group:        "26-35",
  preferred_total_size: 8,
  budget:           "mid",
  wechat_id:        "grace_wx")

make_trip(henry,
  group_type:       "friends",
  group_size:       3,
  group_identity:   nil,
  companion_pref:   "any",
  selected_route:   "full_loop",
  age_group:        "26-35",
  preferred_total_size: 8,
  budget:           "mid",
  wechat_id:        "henry_wx")

# ── Scenario 5: couple joining ────────────────────────────────────────────────
# Two couples on adjacent routes, slightly different dates.

iris = make_user("iris_openid")
jake = make_user("jake_openid")

make_trip(iris,
  group_type:       "couple",
  group_size:       2,
  group_identity:   nil,
  companion_pref:   "any",
  departure_date:   8.days.from_now.to_date.to_s,
  selected_route:   "alpine",
  age_group:        "46-55",
  preferred_total_size: 6,
  budget:           "luxury",
  wechat_id:        "iris_wx")

make_trip(jake,
  group_type:       "couple",
  group_size:       2,
  group_identity:   nil,
  companion_pref:   "any",
  departure_date:   9.days.from_now.to_date.to_s,
  selected_route:   "southeast",  # adjacent to alpine
  age_group:        "46-55",
  preferred_total_size: 6,
  budget:           "luxury",
  wechat_id:        "jake_wx")

# ── Scenario 6: incompatible pair (will NOT match) ────────────────────────────
# female_only traveler vs a male traveler — hard filter should block them.

kate = make_user("kate_openid")
leo  = make_user("leo_openid")

make_trip(kate,
  group_type:       "solo",
  group_size:       1,
  group_identity:   "female",
  companion_pref:   "female_only",
  is_rainbow:       false,
  selected_route:   "kaikoura",
  age_group:        "18-25",
  preferred_total_size: 4,
  budget:           "budget",
  wechat_id:        "kate_wx")

make_trip(leo,
  group_type:       "solo",
  group_size:       1,
  group_identity:   "male",
  companion_pref:   "any",
  is_rainbow:       false,
  selected_route:   "kaikoura",
  age_group:        "18-25",
  preferred_total_size: 4,
  budget:           "budget",
  wechat_id:        "leo_wx")

# ── Scenario 7: stale request (15+ days waiting) ─────────────────────────────
# Force-match candidate — been waiting long enough to lower all thresholds.

mia = make_user("mia_openid")
ned = make_user("ned_openid")

[ mia, ned ].each_with_index do |u, i|
  trip = make_trip(u,
    group_type:       "friends",
    group_size:       2,
    group_identity:   nil,
    companion_pref:   "any",
    departure_date:   30.days.from_now.to_date.to_s,
    selected_route:   i.zero? ? "alpine" : "southeast",
    age_group:        "55+",
    preferred_total_size: 6,
    budget:           i.zero? ? "budget" : "luxury",
    wechat_id:        "#{u.openid}_wx")
  trip.update_columns(created_at: 16.days.ago)
end

puts "Seeded #{User.count} users and #{TripRequest.count} trip requests."
puts "Run MatchingService.run in the console to trigger matching."
