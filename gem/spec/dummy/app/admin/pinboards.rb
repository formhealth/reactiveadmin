module ActiveAdmin::Views
  class IndexAsExploding < ActiveAdmin::Component
    def self.index_name = "exploding"

    def build(page_presenter, collection)
      raise "boom: #{collection.first&.title}"
    end
  end
end

# Presenter options that differ per `index as:`.
ActiveAdmin.register Sketch, as: "Pinboard" do
  menu false

  index title: "Pin table", per_page: [5, 10] do
    column :title
  end

  index as: :grid, title: "Pin grid", columns: 4, paginator: false, download_links: false,
    blank_slate_link: -> { link_to "Pin the first one", "/admin/pinboards/new" } do |sketch|
    h3 sketch.title
  end

  index as: :blog, title: "Pin blog", per_page: [3, 6], download_links: [:csv] do
    title :title
  end

  index as: ActiveAdmin::Views::IndexAsExploding
end

# Grid first, with a table still declared.
ActiveAdmin.register Sketch, as: "Wall" do
  menu false

  index as: :grid, default: true do |sketch|
    h3 sketch.title
  end

  index do
    column :title
  end
end
