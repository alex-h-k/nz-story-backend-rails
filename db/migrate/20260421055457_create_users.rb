class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :openid, null: false

      t.timestamps
    end
    add_index :users, :openid, unique: true
  end
end
