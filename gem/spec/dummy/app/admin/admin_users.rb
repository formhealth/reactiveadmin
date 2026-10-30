# What a host must never let through the API: role changes and impersonation stay in the classic admin.
ActiveAdmin.register AdminUser do
  menu false

  permit_params :name, :email, :role, author_attributes: [:id, :name, :rating, {profile_attributes: [:id, :bio]}]

  filter :name

  api :deny, only: [:create, :destroy, :impersonate, :sweep, :promote]
  api :deny, attributes: [:role, :rating, :bio], reason: "Roles and ratings are changed in the classic admin"

  batch_action :promote do |ids|
    redirect_to collection_path, notice: "Promoted #{ids.size}"
  end

  batch_action :tidy do |ids|
    redirect_to collection_path, notice: "Tidied #{ids.size}"
  end

  member_action :impersonate, method: [:get, :post] do
    redirect_to resource_path(resource), notice: "Impersonating"
  end

  member_action :greet, method: :post do
    redirect_to resource_path(resource), notice: "Hello"
  end

  collection_action :sweep, method: :post do
    redirect_to collection_path, notice: "Swept"
  end

  action_item :impersonate, only: :show do
    link_to "Impersonate", impersonate_admin_admin_user_path(resource), method: :post
  end

  form do |f|
    f.inputs do
      f.input :name
      f.input :email
      f.input :role
    end
    f.semantic_fields_for :author, (f.object.author || f.object.build_author) do |author|
      author.inputs "Author" do
        author.input :name
        author.input :rating
      end
    end
    f.actions
  end
end
