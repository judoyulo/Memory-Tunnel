class CreateChapters < ActiveRecord::Migration[8.0]
  def change
    create_table :chapters, id: :uuid do |t|
      t.references :member_a, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.references :member_b,              foreign_key: { to_table: :users }, type: :uuid  # NULL until invitation accepted
      t.string  :invited_phone                      # E.164 phone of invited non-user (pending state)
      t.string  :status, null: false, default: "pending"  # pending | active | archived
      t.string  :name                               # Optional chapter name
      t.string  :life_chapter_tag                   # e.g. "College", "London", "First job"
      t.datetime :last_memory_at                    # Updated on every new Memory — used by decay detection

      t.timestamps
    end

    # Uniqueness: only one chapter per (member_a, member_b) pair once active
    # During pending state uniqueness enforced by (member_a_id, invited_phone)
    add_index :chapters, %i[member_a_id member_b_id], unique: true,
              where: "member_b_id IS NOT NULL", name: "idx_chapters_active_pair"
    add_index :chapters, %i[member_a_id invited_phone], unique: true,
              where: "member_b_id IS NULL", name: "idx_chapters_pending_pair"
    add_index :chapters, :status
    add_index :chapters, :last_memory_at
  end
end
