ActiveAdmin.register Tag, as: "Badge" do
  menu false

  permit_params :name

  member_action :retire, method: :delete do
    redirect_to collection_path, notice: "Retired"
  end

  member_action :pin, method: :post do
    redirect_to resource_path, notice: "Pinned"
  end

  collection_action :seed, method: :post do
    redirect_to collection_path, notice: "Seeded"
  end

  collection_action :purge, method: :delete do
    redirect_to collection_path, notice: "Purged"
  end

  action_item(:index_only, only: :index) { link_to "Index only", "/admin/badges" }
  action_item(:except_index, except: :index) { link_to "Not on index", "/admin/badges" }
  action_item(:when_empty, only: :index, if: -> { Tag.none? }) { link_to "Seed", seed_admin_badges_path, method: :post }
  action_item(:when_present, only: :index, if: -> { Tag.any? }) { link_to "Purge all", purge_admin_badges_path, method: :delete, data: {confirm: "Purge every badge?"} }
  action_item(:retire, only: :show) do
    link_to "Retire", retire_admin_badge_path(resource), data: {method: :delete, confirm: "Retire this badge?"}
  end

  show do
    attributes_table { row :name }
    panel "Pin" do
      button_to "Pin it", pin_admin_badge_path(resource), method: :post, data: {confirm: "Pin this badge?"}
    end
  end
end
