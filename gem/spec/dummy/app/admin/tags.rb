ActiveAdmin.register Tag do
  menu parent: "Content", priority: 5

  permit_params :name

  filter :name

  index pagination_total: false, download_links: false, per_page: [5, 15], paginator: false do
    column :name
    column :created_at
    actions
  end
end
