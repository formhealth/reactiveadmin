ActiveAdmin.register Comment do
  belongs_to :post

  permit_params :body, :approved

  filter :body
  filter :approved, as: :boolean
  filter :post

  index do
    id_column
    column :body
    column :approved
    column :context
    column :post
    actions
  end

  show do
    attributes_table do
      row :body
      row :context
    end
  end

  form do |f|
    f.inputs do
      f.input :body
      f.input :approved
    end
    f.actions
  end
end
