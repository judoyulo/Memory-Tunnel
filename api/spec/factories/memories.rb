FactoryBot.define do
  factory :memory do
    association :chapter
    association :owner, factory: :user
    s3_key      { "memories/#{SecureRandom.uuid}.jpg" }
    visibility  { "this_item" }
  end
end
