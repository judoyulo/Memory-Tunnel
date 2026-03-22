class CreateDailyCardQueue < ActiveRecord::Migration[8.0]
  # Tracks which card was delivered to which user on which day.
  # Prevents duplicate delivery and supports the one-card-per-day constraint.
  #
  # Priority ranking (stored in trigger_type):
  #   birthday  > decay > manual
  #
  # When multiple triggers fire on the same day, highest-priority wins.
  # Excess triggers are queued for the next available day.
  def change
    create_table :daily_card_queue_entries, id: :uuid do |t|
      t.references :user,    null: false, foreign_key: true, type: :uuid
      t.references :chapter, null: false, foreign_key: true, type: :uuid
      t.string  :trigger_type, null: false  # birthday | decay | manual
      t.integer :priority,     null: false  # 1=birthday, 2=decay, 3=manual (lower = higher priority)
      t.date    :scheduled_for, null: false # The calendar date this card is scheduled for
      t.datetime :delivered_at              # NULL until APNs push sent
      t.datetime :opened_at                # NULL until user taps the notification

      t.timestamps
    end

    add_index :daily_card_queue_entries, %i[user_id scheduled_for], unique: true,
              name: "idx_daily_queue_one_per_day"
    add_index :daily_card_queue_entries, %i[user_id delivered_at]
    add_index :daily_card_queue_entries, :scheduled_for
  end
end
