# Scope groups that interleave in the declaration, with a default, an `if:` and `show_count: false` inside groups.
ActiveAdmin.register Plan do
  menu false
  actions :index
  filter :name

  scope(:free, group: :tier, default: true) { |plans| plans.where("name LIKE 'Free%'") }
  scope(:pro, group: :tier) { |plans| plans.where("name LIKE 'Pro%'") }
  scope(:retired) { |plans| plans.where("name LIKE 'Retired%'") }
  scope(:monthly, group: :billing) { |plans| plans.where("name LIKE '%Monthly'") }
  scope(:enterprise, group: :tier) { |plans| plans.where("name LIKE 'Enterprise%'") }
  scope(:annual, group: :billing, show_count: false) { |plans| plans.where("name LIKE '%Annual'") }
  scope(:internal, group: :billing, if: -> { current_admin_user.role == "admin" }) { |plans| plans.where("name LIKE 'Internal%'") }

  index do
    column :name
    actions
  end
end
