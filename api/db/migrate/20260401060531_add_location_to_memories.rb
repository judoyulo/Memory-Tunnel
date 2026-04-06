class AddLocationToMemories < ActiveRecord::Migration[8.1]
  def change
    add_column :memories, :location_name, :string
    add_column :memories, :latitude, :decimal, precision: 10, scale: 6
    add_column :memories, :longitude, :decimal, precision: 10, scale: 6
  end
end
