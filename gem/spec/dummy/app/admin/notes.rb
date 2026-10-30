ActiveAdmin.register Note do
  menu false

  permit_params :title, :body, :weight

  form do |f|
    f.inputs do
      f.input :title
      f.input :body
      f.input :weight, input_html: {disabled: true}
    end
  end

  filter :title, as: :check_boxes, collection: -> { %w[Alpha Beta] }
  filter :weight, as: :check_boxes, collection: [1, 2, 3], multiple: true

  order_by(:title_length) { |clause| "length(notes.title) #{clause.order}" }

  index title: -> { "Notes (#{Note.count})" },
    blank_slate_link: -> { link_to "Write the first note", new_admin_note_path },
    row_class: ->(note) { note.title.start_with?("!") ? "row-warning flagged" : [] } do
    selectable_column
    index_column
    column :title
    column("Length", sortable: :title_length) { |note| note.title.size }
    column :weight
    column("Slug", sortable: "lower(title)") { |note| note.title.parameterize }
    column("Chars", class: "col-number") { |note| note.body.to_s.size }
    column :created_at, class: "text-center"
    actions name: "Tools", dropdown: true, dropdown_name: "More" do |note|
      item "Open", admin_note_path(note)
    end
  end

  index as: :grid, columns: 2 do |note|
    h3 note.title
    para note.body
  end

  index as: :blog do
    title :title
    body ->(note) { "Weight #{note.weight}" }
  end

  index as: :block do |note|
    div(class: "note_block") { h4 note.title }
  end

  sidebar "Note stats", only: :index do
    para "Total: #{Note.count}"
  end
end
