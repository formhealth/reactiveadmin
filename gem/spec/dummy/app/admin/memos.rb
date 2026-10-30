# No index or show block: exercises implicit (secure) defaults.
ActiveAdmin.register Memo do
  menu false

  belongs_to :author, optional: true

  permit_params :title, :summary, :payload, :secret, :priority, :pinned, :author_id

  filter :title

  controller do
    # Dereferences the parent: fine nested under an author, a NoMethodError on the unnested route.
    def new = super { resource.summary = "Draft by #{resource.author.name}" }
  end
end
