class AddIsRainbowToTripRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :trip_requests, :is_rainbow, :boolean
  end
end
