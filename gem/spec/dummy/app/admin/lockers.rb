ActiveAdmin.register Locker do
  menu false

  permit_params :label, :code

  filter :label

  api :deny, only: :edit
end
