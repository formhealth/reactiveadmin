ActiveAdmin.register Author do
  menu parent: ["Content", "People"]

  permit_params :name, :email, :rating, :born_on, profile_attributes: [:id, :bio]

  filter :name
  filter :rating, as: :numeric
  filter :born_on, as: :date_range

  index do
    selectable_column
    id_column
    column :name
    column(:email) { |author| author.email && mail_to(author.email) }
    column :rating
    actions defaults: false do |author|
      item "Ping", ping_admin_author_path(author), method: :post
    end
  end

  member_action :ping, method: :post do
    redirect_to resource_path, notice: "Pinged #{resource.name}"
  end

  show do
    attributes_table do
      row :name
      row :email
      row :rating
      row :born_on
    end
  end

  form do |f|
    f.inputs do
      f.input :name
      f.input :email
      f.input :rating
      f.input :born_on, as: :datepicker
    end
    f.semantic_fields_for :profile, (f.object.profile || f.object.build_profile) do |profile|
      profile.inputs "Profile" do
        profile.input :bio
      end
    end
    f.actions do
      f.action :submit, button_html: {data: {confirm: "Save this author?"}}
    end
  end

  controller do
    def find_resource = scoped_collection.find(params[:id])
  end
end
