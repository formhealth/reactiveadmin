ActiveAdmin.register_page "Ops Links" do
  menu false

  action_item(:sidekiq) { link_to "Sidekiq Dashboard", "/sidekiq" }

  content do
    para { link_to "12 retries", "/sidekiq/retries?substr=Foo" }
    para { link_to "Posts", "/admin/posts" }
  end
end
