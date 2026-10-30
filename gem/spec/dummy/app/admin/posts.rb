ActiveAdmin.register Post do
  menu parent: "Content", priority: 1

  permit_params :title, :body, :status, :published_at, :author_id, :category_id, :featured,
    metadata: {}, tag_ids: [], comments_attributes: [:id, :body, :approved, :_destroy]

  scope :all, default: true
  scope :draft, group: :status
  scope :published, group: :status
  scope :archived, group: :status, show_count: false
  scope :featured, if: -> { current_admin_user.role == "admin" }

  filter :title
  filter :views_count
  filter :published_at, as: :date_range
  filter :status, as: :select, collection: -> { Post.statuses }
  filter :featured, as: :boolean
  filter :category, as: :check_boxes, collection: -> { Category.all }
  filter :author_id_eq, label: "Author", as: :typeahead, source: :authors
  filter :tags

  index do
    selectable_column
    id_column
    column :title
    column(:status) { |post| status_tag post.status }
    column :author
    column("Views", sortable: :views_count) { |post| number_with_delimiter(post.views_count) }
    column("Link") { |post| link_to "Open", admin_post_path(post) }
    column :published_at
    actions defaults: false do |post|
      item "Preview", preview_admin_post_path(post)
      item "Publish", publish_admin_post_path(post), method: :put
    end
  end

  sidebar "Post stats", only: :index do
    para "Total: #{Post.count}"
    ul { li "Featured: #{Post.where(featured: true).count}" }
  end

  sidebar "Hidden", only: :index, if: -> { false } do
    para "never"
  end

  sidebar "Views", only: :show, if: -> { resource.views_count.positive? }, priority: 5 do
    attributes_table_for(resource) { row :views_count }
  end

  csv do
    column :id
    column :title
    column(:author) { |post| post.author.name }
  end

  batch_action :set_status, form: {status: %w[draft published archived], note: :text} do |ids, inputs|
    batch_action_collection.find(ids).each { |post| post.update!(status: inputs["status"]) }
    redirect_to collection_path, notice: "Updated #{ids.size} posts to #{inputs["status"]}"
  end

  batch_action :feature, confirm: "Feature these posts?" do |ids|
    batch_action_collection.find(ids).each { |post| post.update!(featured: true) }
    redirect_to collection_path, notice: "Featured #{ids.size} posts"
  end

  batch_action :admins_only, if: proc { current_admin_user.role == "admin" } do |ids|
    redirect_to collection_path, notice: "Done #{ids.size}"
  end

  reactive do
    expose :stats
    expose :rename
    expose :audit
  end

  member_action :rename, method: [:get, :post] do
    if request.post?
      resource.update!(title: params.dig(:post, :title))
      redirect_to resource_path(resource), notice: "Renamed"
    end
  end

  member_action :preview, method: :get

  member_action :audit, method: :get

  member_action :note, method: :get

  member_action :publish, method: :put do
    resource.published!
    redirect_to resource_path, notice: "Published #{resource.title}"
  end

  member_action :archive, method: :post do
    resource.archived!
    redirect_to resource_path, notice: "Archived"
  end

  member_action :flag, method: :post do
    redirect_to resource_path(resource), alert: "Cannot flag this post"
  end

  collection_action :stats, method: :get

  collection_action :import, method: :post do
    redirect_to collection_path, notice: "Imported"
  end

  action_item :publish, only: :show, if: -> { !resource.published? } do
    link_to "Publish", publish_admin_post_path(resource), method: :put
  end

  action_item :archive, only: :show do
    link_to "Archive", archive_admin_post_path(resource), method: :post, data: {confirm: "Archive this post?"}
  end

  action_item :import, only: :index do
    link_to "Import", import_admin_posts_path, method: :post
  end

  show do
    tabs do
      tab "Details" do
        attributes_table do
          row :title
          row(:status) { |post| status_tag post.status }
          row :author
          row :published_at
          row :featured
          row :metadata
        end
      end
      tab "Comments" do
        panel "Comments" do
          table_for resource.comments do
            column :body
            column :approved
          end
        end
      end
    end
    columns do
      column do
        panel "Info" do
          para "Views: #{resource.views_count}"
        end
      end
      column do
        panel "Tags" do
          ul { resource.tags.each { |tag| li tag.name } }
        end
      end
    end
    panel "Moderation" do
      button_to "Flag", flag_admin_post_path(resource), method: :post
    end
  end

  form do |f|
    f.semantic_errors
    f.inputs "Details" do
      f.input :title
      f.input :body
      f.input :status, as: :select, collection: Post.statuses.keys, include_blank: false
      f.input :author, as: :typeahead, source: :authors
      f.input :category
      f.input :featured
      f.input :published_at, as: :datetime_picker
      f.input :metadata
    end
    f.inputs "Tags" do
      f.input :tags, as: :check_boxes
    end
    f.has_many :comments, allow_destroy: true, new_record: "Add comment" do |comment|
      comment.input :body
      comment.input :approved
    end
    f.actions
  end

  controller do
    def scoped_collection = super.includes(:author)

    def update
      resource.assign_attributes(permitted_params[:post])
      if resource.save
        redirect_to resource_path, notice: "Post saved"
      else
        render :edit
      end
    end
  end
end
