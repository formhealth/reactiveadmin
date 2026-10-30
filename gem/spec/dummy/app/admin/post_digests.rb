ActiveAdmin.register_page "Post Digests" do
  menu false
  belongs_to :post

  content { para "Digest" }
end
