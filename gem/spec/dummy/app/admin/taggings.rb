module ActiveAdmin::Views
  class IndexAsTaglist < ActiveAdmin::Component
    def self.index_name = "taglist"

    def build(page_presenter, collection)
      add_class "index"
      ul { collection.each { |tagging| li "#{tagging.tag.name} on #{tagging.post.title}" } }
    end
  end
end

ActiveAdmin.register Tagging do
  menu false

  permit_params :post_id, :tag_id

  index as: ActiveAdmin::Views::IndexAsTaglist

  form do |f|
    f.inputs { f.input :post_id }
    div { text_node '<input type="text" name="tagging[note]">'.html_safe }
  end
end
