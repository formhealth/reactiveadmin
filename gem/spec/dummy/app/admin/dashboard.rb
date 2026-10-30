ActiveAdmin.register_page "Dashboard" do
  menu priority: 1, label: "Dashboard"

  content title: "Dashboard" do
    text_node reactiveadmin_ui_toggle
    panel "Stats" do
      para "Posts: #{Post.count}"
    end
  end

  page_action :recalc, method: :post do
    redirect_to admin_dashboard_path, notice: "Recalculated"
  end

  action_item :recalc do
    link_to "Recalculate", admin_dashboard_recalc_path, method: :post
  end
end
