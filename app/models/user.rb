class User < ApplicationRecord
  has_many :trip_requests, dependent: :destroy

  validates :openid, presence: true, uniqueness: true
end
