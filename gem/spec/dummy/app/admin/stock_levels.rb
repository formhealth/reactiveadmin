ActiveAdmin.register StockLevel do
  menu false

  permit_params :quantity

  filter :warehouse
  filter :quantity

  index do
    id_column
    column :quantity
    column :details
    actions
  end
end
