ActiveAdmin.register_page "Legacy Forms" do
  menu false

  content do
    render partial: "admin/legacy_forms/forms"
  end
end
