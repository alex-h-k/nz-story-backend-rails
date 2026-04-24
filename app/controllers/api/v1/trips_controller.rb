module Api
  module V1
    class TripsController < ApplicationController
      before_action :require_openid, only: [ :create, :show ]

      # POST /api/v1/trips
      def create
        user = User.find_or_create_by!(openid: current_openid)

        t = params[:trip] || params

        return render json: { message: "departureDate is required" }, status: :bad_request if t[:departureDate].blank?
        return render json: { message: "wechatId is required" },      status: :bad_request if t[:wechatId].blank?
        return render json: { message: "groupingPref is required" },   status: :bad_request if t[:groupingPref].blank?

        Rails.logger.info("[POST /trips] incoming form → #{t.to_unsafe_h.to_json}")

        trip = user.trip_requests.build(
          openid:              current_openid,
          departure_date:      t[:departureDate],
          group_type:          t[:groupType].presence,
          group_size:          t[:groupSize].to_i.then { |n| n > 0 ? n : 1 },
          child_count:         t[:childCount].to_i,
          grouping_pref:       t[:groupingPref],
          route_mode:          t[:routeMode].presence || "preset",
          selected_route:      t[:selectedRoute].presence,
          custom_days:         t[:customDays].presence&.to_i,
          group_identity:      t[:groupIdentity].presence,
          companion_pref:      t[:companionPref].presence,
          age_group:           t[:ageGroup].presence,
          preferred_age_group: t[:preferredAgeGroup].presence,
          preferred_total_size: t[:preferredTotalSize].presence&.to_i,
          budget:              t[:budget].presence,
          contact_type:        t[:contactType].presence || "self",
          wechat_id:           t[:wechatId],
          notes:               t[:notes].presence
        )

        unless trip.save
          return render json: { message: trip.errors.full_messages.first }, status: :unprocessable_entity
        end

        # Run matching immediately after submission (also runs via recurring job)
        MatchingJob.perform_later

        render json: { id: trip.id, status: trip.status }, status: :created
      end

      # GET /api/v1/trips/:id
      def show
        trip = TripRequest.find_by(id: params[:id])

        return render json: { message: "not found" },  status: :not_found  unless trip
        return render json: { message: "forbidden" },  status: :forbidden   unless trip.openid == current_openid

        matched_with = nil
        if trip.matched_with_id
          partner = TripRequest.find_by(id: trip.matched_with_id)
          matched_with = { wechatId: partner.wechat_id, groupSize: partner.group_size } if partner
        end

        render json: {
          id:          trip.id,
          status:      trip.status,
          matchScore:  trip.match_score,
          matchType:   trip.match_type,
          matchedAt:   trip.matched_at,
          matchedWith: matched_with
        }
      end

      # POST /api/v1/trips/match/run  (admin / dev)
      def run_match
        result = MatchingService.run
        render json: { ok: true }.merge(result)
      rescue => e
        render json: { ok: false, error: e.message }, status: :internal_server_error
      end

      private

      def require_openid
        render json: { message: "missing openid" }, status: :unauthorized unless current_openid
      end

      def current_openid
        request.headers["X-Wechat-Openid"]
      end
    end
  end
end
