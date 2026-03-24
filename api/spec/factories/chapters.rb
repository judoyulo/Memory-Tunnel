FactoryBot.define do
  factory :chapter do
    association :member_a, factory: :user
    status { "pending" }
    invited_phone { "+14155550199" }

    trait :active do
      association :member_b, factory: :user
      status { "active" }
      invited_phone { nil }
    end
  end
end
