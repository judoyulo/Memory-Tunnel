FactoryBot.define do
  factory :invitation do
    association :chapter
    association :invited_by, factory: :user
    association :preview_memory, factory: :memory
    expires_at { 7.days.from_now }

    trait :expired do
      expires_at { 1.day.ago }
    end
  end
end
