ActiveAdmin.register Plan, as: "ConstructPlan" do
  menu false

  reactive { mask :api_token }

  scope :all, default: true
  scope(:with_notes, if: -> { current_admin_user.role == "admin" }) { |plans| plans.where.not(notes: "") }

  # AA runs a filter's `if:` and `unless:` with the view as an argument, so they must be procs, not lambdas.
  filter :name, as: :select, collection: -> { Plan.where("coalesce(notes, '') LIKE ?", "%#{params.dig(:q, :notes_cont)}%").order(:name).pluck(:name) }
  filter :notes
  filter :updated_at, if: proc { current_admin_user.role == "admin" }
  filter :id, unless: proc { current_admin_user.role == "admin" }
  filter :created_at, if: proc { false }

  index do
    column :name
    column(:notes) { |plan| plan.notes.to_s.upcase }
    column("Name length", sortable: :name_length) { |plan| plan.name.size }
    actions do |plan|
      item "Rename", admin_construct_plan_path(plan)
      item "Gold only", admin_construct_plan_path(plan) if plan.name == "Gold"
    end
  end

  order_by(:name_length) { |clause| "length(plans.name) #{clause.order}" }
end
