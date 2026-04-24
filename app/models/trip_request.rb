class TripRequest < ApplicationRecord
  belongs_to :user

  belongs_to :matched_with,
    class_name: "TripRequest",
    foreign_key: :matched_with_id,
    optional: true

  validates :departure_date, :grouping_pref, :route_mode, :wechat_id, presence: true
  validates :grouping_pref, inclusion: { in: %w[join_group solo_group] }, allow_nil: true
  validates :group_identity, inclusion: { in: %w[male female] }, allow_nil: true
  validates :companion_pref, inclusion: { in: %w[any male_only female_only rainbow_friendly] }, allow_nil: true

  scope :waiting,  -> { where(status: "waiting") }
  scope :matched,  -> { where(status: "matched") }
  scope :expired,  -> { where(status: "expired") }
end
