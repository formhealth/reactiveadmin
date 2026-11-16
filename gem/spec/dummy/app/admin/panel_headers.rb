ActiveAdmin.register_page "Panel Headers" do
  menu false

  content do
    panel "Linked" do
      header_action link_to("Edit", "/admin/posts")
      para "Body"
    end
    panel "Acting" do
      header_action link_to("Archive", "/admin/panel_headers/archive", method: :post, data: {confirm: "Sure?"})
      para "Body"
    end
    panel "Plain" do
      header_action tag.em("not an action")
      para "Body"
    end
  end

  page_action :archive, method: :post do
    redirect_to admin_panel_headers_path, notice: "Archived"
  end
end
