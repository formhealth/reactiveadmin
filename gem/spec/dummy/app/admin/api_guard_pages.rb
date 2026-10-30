ActiveAdmin.register_page "Danger Zone" do
  menu false

  content { para "Careful" }

  page_action :wipe, method: :post do
    redirect_to admin_danger_zone_path, notice: "Wiped"
  end

  page_action :audit, method: :get

  api :deny, only: [:wipe, :audit]
end

ActiveAdmin.register_page "Back Office" do
  menu false

  content { para "Staff only" }

  api false
end
