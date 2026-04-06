class AddTimelineAndWelcomeFields < ActiveRecord::Migration[7.1]
  def change
    # Plan 1: Chapter timeline fields on memories
    add_column :memories, :event_date, :date
    add_column :memories, :emotion_tags, :string, array: true, default: []
    add_column :memories, :width, :integer
    add_column :memories, :height, :integer

    # Plan 2: Welcome card tracking on users
    add_column :users, :welcomed_at, :datetime
  end
end
