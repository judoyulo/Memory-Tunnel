class ChangeS3KeyNullableOnMemories < ActiveRecord::Migration[8.1]
  def change
    change_column_null :memories, :s3_key, true
  end
end
