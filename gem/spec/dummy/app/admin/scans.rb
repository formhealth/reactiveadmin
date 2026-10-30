# No index or show block: a binary column under secure defaults.
ActiveAdmin.register Scan do
  menu false

  permit_params :title

  filter :title

  form do |f|
    f.inputs { f.input :title }
  end
end
