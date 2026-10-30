# Form constructs that must record the way classic renders them: inputs chosen by who is signed in,
# a hidden association input, and `heading: true`.
ActiveAdmin.register Article do
  menu false

  permit_params :title, :author_id, :featured, :views_count, comments_attributes: [:id, :body, :_destroy]

  filter :title

  # Stored text printed as html next to a control the DSL built: only the second may become an action.
  show do
    attributes_table do
      row("Stored") { |article| raw(article.title) }
      row("Control") { |article| link_to "Remove", admin_article_path(article), method: :delete, data: {confirm: "Remove it?"} }
    end
  end

  form do |f|
    f.inputs do
      f.input :title
      f.input :author, as: :hidden
      if current_active_admin_user.editor?
        f.input :featured
      else
        f.input :views_count
      end
    end
    f.has_many :comments, heading: true, max_rows: 5 do |comment|
      comment.input :body, as: :string
    end
    f.actions
  end
end
