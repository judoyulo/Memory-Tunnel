class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    create_table :users, id: :uuid do |t|
      t.string  :phone,        null: false          # E.164 format, e.g. +14155551234
      t.string  :display_name, null: false
      t.string  :avatar_url
      t.string  :push_token                         # APNs device token (nullable — user may deny)
      t.string  :otp_code                           # bcrypt digest of the 6-digit code
      t.datetime :otp_expires_at

      t.timestamps
    end

    add_index :users, :phone, unique: true
  end
end
