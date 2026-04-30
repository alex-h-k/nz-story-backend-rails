class AddTripDaysToTripRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :trip_requests, :trip_days, :integer
  end
end
