ActiveAdmin.register Sketch do
  menu false

  permit_params :title, :weight

  filter :title

  form partial: "form"
end
