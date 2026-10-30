ActiveAdmin.register Profile do
  menu false

  permit_params :bio

  filter :bio

  api false, reason: "Profiles are managed in the classic admin"
end
