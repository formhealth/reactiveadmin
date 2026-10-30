ActiveAdmin.register_page "Post Previews" do
  menu false

  content { para Post.find(params[:post_id]).title }
end
