class AddMediaTypeToMemories < ActiveRecord::Migration[8.1]
  def change
    add_column :memories, :media_type, :string, null: false, default: "photo"
    add_index  :memories, [:chapter_id, :media_type]
  end
end
