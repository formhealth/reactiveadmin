ActiveAdmin.register Offer do
  menu false
  actions :index
  filter :name

  scope :all, default: true
  scope(:trial, group: :kind) { |offers| offers.where("name LIKE 'Trial%'") }
  scope(:paid, group: :kind) { |offers| offers.where("name LIKE 'Paid%'") }

  index scope_count: false do
    column :name
    actions
  end
end
