class CreateMemories < ActiveRecord::Migration[8.0]
  def change
    create_table :memories, id: :uuid do |t|
      t.references :chapter, null: false, foreign_key: true, type: :uuid
      t.references :owner,   null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string  :s3_key,     null: false    # S3 object key — signed URL generated on read
      t.string  :caption
      t.datetime :taken_at                  # From EXIF if available; falls back to created_at
      t.string  :visibility, null: false, default: "this_item"  # this_item | all

      t.timestamps
    end

    add_index :memories, %i[chapter_id created_at]
    add_index :memories, %i[chapter_id owner_id visibility]
  end
end
