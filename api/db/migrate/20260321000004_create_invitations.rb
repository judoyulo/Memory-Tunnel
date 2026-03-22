class CreateInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :invitations, id: :uuid do |t|
      t.references :chapter,        null: false, foreign_key: true, type: :uuid
      t.references :invited_by,     null: false, foreign_key: { to_table: :users }, type: :uuid
      t.references :preview_memory, null: false, foreign_key: { to_table: :memories }, type: :uuid
      t.string  :token,      null: false   # Opaque, server-generated, URL-safe random token
      t.datetime :expires_at, null: false  # created_at + 7 days
      t.datetime :accepted_at             # NULL until receiver accepts

      t.timestamps
    end

    add_index :invitations, :token, unique: true
    add_index :invitations, :accepted_at
    add_index :invitations, :expires_at
  end
end
