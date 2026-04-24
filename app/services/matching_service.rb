class MatchingService
  # Route stop lists (mirrors frontend PRESET_ROUTES)
  ROUTE_STOPS = {
    "kaikoura"  => %w[christchurch kaikoura],
    "alpine"    => %w[christchurch tekapo mtcook wanaka queenstown],
    "southeast" => %w[queenstown dunedin oamaru christchurch],
    "full_loop" => %w[christchurch kaikoura tekapo mtcook wanaka queenstown milford dunedin oamaru],
    "fiordland" => %w[queenstown te_anau milford doubtful]
  }.freeze

  ADJACENT_ROUTES = {
    "alpine"    => %w[southeast fiordland],
    "southeast" => %w[alpine],
    "fiordland" => %w[alpine southeast],
    "full_loop" => %w[kaikoura alpine southeast fiordland],
    "kaikoura"  => %w[full_loop alpine]
  }.freeze

  BUDGET_ORDER  = %w[budget mid luxury].freeze
  DATE_SCORES   = [ 30, 24, 16, 8 ].freeze   # index = day diff (0-3)
  SCORE_IDEAL   = 70
  SCORE_OK      = 50

  AGE_GROUPS = %w[18-25 26-35 36-45 46-55 55+].freeze

  def self.run
    new.run
  end

  def self.run_fallback
    new.run_fallback
  end

  # ── Main matching job ─────────────────────────────────────────────────────────

  def run
    waiting = TripRequest.waiting.order(:created_at).to_a

    if waiting.size < 2
      Rails.logger.info("[matching] #{waiting.size} request(s) waiting — nothing to pair")
      return { paired: 0, forced: 0 }
    end

    Rails.logger.info("[matching] evaluating #{waiting.size} waiting requests")

    candidates = []

    waiting.each_with_index do |a, i|
      days_a   = days_waiting(a)
      thresh_a = thresholds(days_a)

      waiting[(i + 1)..].each do |b|
        days_b   = days_waiting(b)
        thresh_b = thresholds(days_b)

        next unless _pass_hard_filters?(a, b, thresh_a, thresh_b)

        score     = _calc_score(a, b)
        min_score = [ thresh_a[:min_score], thresh_b[:min_score] ].min

        next unless score >= min_score

        is_forced = [ days_a, days_b ].max >= 15
        candidates << { a: a, b: b, score: score, forced: is_forced }
      end
    end

    # Greedy: highest score first, each request paired at most once
    candidates.sort_by! { |c| -c[:score] }

    matched = Set.new
    paired  = 0
    forced  = 0

    candidates.each do |c|
      a, b = c[:a], c[:b]
      next if matched.include?(a.id) || matched.include?(b.id)

      confirm_match(a, b, c[:score], c[:forced])
      matched.add(a.id)
      matched.add(b.id)
      paired += 1
      forced += 1 if c[:forced]
    end

    Rails.logger.info("[matching] done — #{paired} pair(s) confirmed (#{forced} forced)")
    { paired: paired, forced: forced }
  end

  # ── Fallback: expire stale requests, log overdue ones ────────────────────────

  def run_fallback
    cutoff = 30.days.ago.to_date.to_s

    expired_count = TripRequest.waiting
      .where("departure_date < ?", cutoff)
      .update_all(status: "expired")

    Rails.logger.info("[fallback] expired #{expired_count} stale request(s)")

    overdue = TripRequest.waiting
      .where("created_at <= ?", 15.days.ago)

    if overdue.any?
      Rails.logger.warn("[fallback] ⚠ #{overdue.count} request(s) waiting 15+ days — review needed")
      overdue.each do |r|
        Rails.logger.warn("  ##{r.id} | departs #{r.departure_date} | submitted #{r.created_at.to_date}")
      end
    end

    { expired: expired_count, overdue: overdue.count }
  end

  # ── Public helpers (also used in specs) ──────────────────────────────────────

  def calc_score(a, b)
    _calc_score(a, b)
  end

  def pass_hard_filters?(a, b, thresh_a, thresh_b)
    _pass_hard_filters?(a, b, thresh_a, thresh_b)
  end

  private

  # ── Thresholds ────────────────────────────────────────────────────────────────

  def thresholds(days_waiting)
    case days_waiting
    when 0..3  then { min_score: SCORE_IDEAL, max_date_diff: 3, min_overlap: 0.40 }
    when 4..7  then { min_score: SCORE_OK,    max_date_diff: 4, min_overlap: 0.30 }
    when 8..14 then { min_score: 30,          max_date_diff: 5, min_overlap: 0.20 }
    else             { min_score: 0,           max_date_diff: 7, min_overlap: 0.00 }
    end
  end

  # ── Hard filters ──────────────────────────────────────────────────────────────

  def _pass_hard_filters?(a, b, thresh_a, thresh_b)
    return false unless a.grouping_pref == "join_group" && b.grouping_pref == "join_group"

    max_date_diff = [ thresh_a[:max_date_diff], thresh_b[:max_date_diff] ].max
    min_overlap   = [ thresh_a[:min_overlap],   thresh_b[:min_overlap]   ].min

    return false if days_between(a.departure_date, b.departure_date) > max_date_diff

    combined   = a.group_size + b.group_size
    size_limit = [ a.preferred_total_size || 10, b.preferred_total_size || 10, 10 ].min
    return false if combined > size_limit

    overlap    = route_overlap(a, b)
    adjacent   = routes_adjacent?(a, b)
    both_custom = a.route_mode == "custom" && b.route_mode == "custom"
    return false if !both_custom && overlap < min_overlap && !adjacent

    return false unless companion_pref_compatible?(a, b)

    true
  end

  # ── Scoring ───────────────────────────────────────────────────────────────────

  def _calc_score(a, b)
    score = 0

    # Date score (max 30)
    date_diff = days_between(a.departure_date, b.departure_date)
    score += DATE_SCORES[[ date_diff, 3 ].min]

    # Route score (max 35)
    overlap = route_overlap(a, b)
    score += if    overlap >= 1.0        then 35
             elsif overlap >= 0.7        then 28
             elsif overlap >= 0.4        then 18
             elsif routes_adjacent?(a, b) then 10
             else                             0
             end

    # Group size score (max 20)
    combined = a.group_size + b.group_size
    pref_a   = a.preferred_total_size || 10
    pref_b   = b.preferred_total_size || 10
    min_pref = [ pref_a, pref_b ].min
    max_pref = [ pref_a, pref_b ].max
    score += if    combined == min_pref then 20
             elsif combined <= min_pref then 12
             elsif combined <= max_pref then 6
             else                            0
             end

    # Soft preferences (max 15)
    score += 5 if age_groups_close?(a.age_group, b.age_group)
    score += 5 if companion_pref_compatible?(a, b)
    score += if a.budget && a.budget == b.budget then 5
             elsif budget_adjacent?(a.budget, b.budget) then 2
             else 0
             end

    score
  end

  # ── Companion preference compatibility ───────────────────────────────────────
  # group_identity: male / female / nil (solo only; non-solo not collected)
  # companion_pref: any / male_only / female_only / rainbow_friendly (solo only)
  # is_rainbow:     true / false / nil (solo only)

  def companion_pref_compatible?(a, b)
    satisfies = lambda do |pref, other|
      case pref
      when "any"              then true
      when "male_only"        then other.group_identity == "male"
      when "female_only"      then other.group_identity == "female"
      when "rainbow_friendly" then other.is_rainbow == true
      else true
      end
    end

    satisfies.call(a.companion_pref || "any", b) &&
      satisfies.call(b.companion_pref || "any", a)
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  def days_between(date_a, date_b)
    (Date.parse(date_a.to_s) - Date.parse(date_b.to_s)).abs.to_i
  end

  def days_waiting(trip)
    (Date.today - trip.created_at.to_date).to_i
  end

  def route_stops(trip)
    return [] unless trip.route_mode == "preset" && trip.selected_route
    ROUTE_STOPS[trip.selected_route] || []
  end

  def route_overlap(a, b)
    stops_a = route_stops(a)
    stops_b = route_stops(b)
    return 0 if stops_a.empty? || stops_b.empty?

    intersection = (stops_a & stops_b).size
    union        = (stops_a | stops_b).size
    intersection.to_f / union
  end

  def routes_adjacent?(a, b)
    return false unless a.selected_route && b.selected_route
    (ADJACENT_ROUTES[a.selected_route] || []).include?(b.selected_route)
  end

  def age_group_index(group)
    AGE_GROUPS.index(group)
  end

  def age_groups_close?(ga, gb)
    ia = age_group_index(ga)
    ib = age_group_index(gb)
    return false if ia.nil? || ib.nil?
    (ia - ib).abs <= 1
  end

  def budget_adjacent?(ba, bb)
    ia = BUDGET_ORDER.index(ba)
    ib = BUDGET_ORDER.index(bb)
    return false if ia.nil? || ib.nil?
    (ia - ib).abs == 1
  end

  # ── Confirm match (atomic) ────────────────────────────────────────────────────

  def confirm_match(a, b, score, forced)
    match_type = if    score >= SCORE_IDEAL then "ideal"
                 elsif score >= SCORE_OK    then "acceptable"
                 elsif forced               then "forced"
                 else                            "suggested"
                 end

    now = Time.current

    TripRequest.transaction do
      a.update!(status: "matched", matched_with_id: b.id, match_score: score, match_type: match_type, matched_at: now)
      b.update!(status: "matched", matched_with_id: a.id, match_score: score, match_type: match_type, matched_at: now)
    end

    Rails.logger.info("[matching] ✓ matched ##{a.id} ↔ ##{b.id} | score=#{score} | type=#{match_type}")
  end
end
