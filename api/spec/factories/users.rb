FactoryBot.define do
  factory :user do
    sequence(:phone) { |n| "+1650555#{n.to_s.rjust(4, '0')}" }
    display_name { "User" }
  end
end
