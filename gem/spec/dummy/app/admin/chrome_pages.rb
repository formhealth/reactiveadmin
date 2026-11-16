ActiveAdmin.register_page "Chart Embed" do
  menu false

  content do
    para "Above the chart"
    script "window.chartReady = true"
  end
end

ActiveAdmin.register_page "Export Hub" do
  menu false

  content { para "Exports" }

  page_action :summary, method: :get
  page_action :rebuild, method: :post do
    redirect_to admin_export_hub_path, notice: "Rebuilt"
  end

  action_item(:staff_only, if: -> { current_active_admin_user&.role == "admin" }) { link_to "Staff report", "/admin/export_hub/summary" }
  action_item(:hidden, if: -> { false }) { link_to "Hidden", "/admin/export_hub/summary" }
end
