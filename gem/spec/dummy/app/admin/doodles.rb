ActiveAdmin.register Sketch, as: "Doodle" do
  menu false

  permit_params :title, :weight

  form partial: "raw"
end
