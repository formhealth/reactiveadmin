ActiveAdmin.register Category do
  menu priority: 3

  permit_params :name, :api_token

  reactive { mask :api_token }

  filter :name, as: :string
  filter :posts, as: :typeahead, source: :posts
end
