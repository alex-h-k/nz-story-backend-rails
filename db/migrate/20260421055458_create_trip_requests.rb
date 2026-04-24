class CreateTripRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :trip_requests do |t|
      t.references :user,   null: false, foreign_key: true
      t.string     :openid, null: false

      # Schedule
      t.string  :departure_date, null: false   # YYYY-MM-DD

      # Group composition
      t.string  :group_type                    # solo / couple / family / friends
      t.integer :group_size,    null: false, default: 1
      t.integer :child_count,   null: false, default: 0
      t.string  :grouping_pref, null: false    # solo_group / join_group

      # Route
      t.string  :route_mode,    null: false    # preset / custom
      t.string  :selected_route
      t.integer :custom_days

      # Preferences (join_group only)
      t.string  :group_identity                # male / female / mixed / rainbow
      t.string  :companion_pref                # any / female_only / rainbow_friendly
      t.string  :age_group
      t.string  :preferred_age_group
      t.integer :preferred_total_size

      # Budget & contact
      t.string  :budget                        # budget / mid / luxury
      t.string  :contact_type                  # self / other
      t.string  :wechat_id, null: false
      t.text    :notes

      # Matching state
      t.string  :status,          null: false, default: "waiting"  # waiting / matched / expired
      t.integer :matched_with_id
      t.float   :match_score
      t.string  :match_type                    # ideal / acceptable / forced / suggested
      t.datetime :matched_at

      t.timestamps
    end

    add_index :trip_requests, :status
    add_index :trip_requests, :departure_date
    add_index :trip_requests, :matched_with_id
  end
end
