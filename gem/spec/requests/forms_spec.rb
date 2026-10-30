RSpec.describe "forms", type: :request do
  include_context "with a blog"

  let(:form) { json["form"] }
  let(:fields) { fields_of(form) }
  let(:sections) { form["sections"] }

  # Untitled sections are null in the payload but the contract says `title: string`; those forms are
  # validated by their own example instead of everywhere.
  def new_form(resource = "posts", schema: "FormResponse") = api_get("/api/admin/#{resource}/new", schema:)

  def edit_form(record, resource: "posts", schema: "FormResponse") = api_get("/api/admin/#{resource}/#{record.id}/edit", schema:)

  def body(attrs = {}, key: "post", **more) = {key => attrs.merge(more)}

  context "when signed in as an admin" do
    before { sign_in admin }

    it "carries the confirm of the form's submit button" do
      expect(edit_form(alice, resource: "authors", schema: nil)).to include("submit_confirm" => "Save this author?")
      expect(new_form).not_to have_key("submit_confirm")
    end

    describe "GET new" do
      before { new_form }

      it "describes where to submit" do
        expect(json).to include("resource" => "posts", "title" => "New Post", "action" => {"method" => "post", "path" => "/api/admin/posts"})
        expect(json).not_to have_key("id")
        expect(json["permissions"]).to include("create" => true)
      end

      it "turns the form block into sections" do
        expect(sections.pluck("kind", "title")).to eq([["inputs", "Details"], ["inputs", "Tags"], ["has_many", "Comments"]])
      end

      it "types fields from columns and options" do
        expect(fields["title"]).to include("control" => "text", "param" => "post[title]", "required" => true, "value" => nil)
        expect(fields["body"]).to include("control" => "textarea", "required" => false)
        expect(fields["featured"]).to include("control" => "boolean", "param" => "post[featured]", "value" => false)
        expect(fields["published_at"]).to include("control" => "datetime")
        expect(fields["metadata"]).to include("control" => "json", "param" => "post[metadata]")
      end

      it "inlines select options and the default value" do
        expect(fields["status"]).to include("control" => "select", "param" => "post[status]", "value" => "draft")
        expect(fields["status"]["options"].pluck("value")).to eq(%w[draft published archived])
      end

      it "inlines association selects" do
        expect(fields["category"]).to include("control" => "select", "param" => "post[category_id]")
        expect(fields["category"]["options"]).to eq([{"label" => "News", "value" => news.id.to_s}])
      end

      it "types `as: :typeahead, source:` as a typeahead carrying the source's options when few" do
        expect(fields["author"]).to include("control" => "typeahead", "param" => "post[author_id]", "required" => true, "free_text" => true)
        expect(fields["author"]["options"]).to eq([{"label" => "Alice Author", "value" => alice.id.to_s}, {"label" => "Bob Builder", "value" => bob.id.to_s}])
      end

      it "describes has_many with a template for new rows" do
        comments = sections.last

        expect(comments).to include("name" => "comments", "param_key" => "comments_attributes", "param" => "post[comments_attributes]",
          "allow_destroy" => true, "new_record_label" => "Add comment", "records" => [])
        expect(comments["template_fields"].pluck("name", "param", "control")).to eq([
          ["body", "post[comments_attributes][__INDEX__][body]", "textarea"],
          ["approved", "post[comments_attributes][__INDEX__][approved]", "boolean"]
        ])
      end

      it "carries no header actions on the form" do
        expect(json["actions"]).to eq([])
      end
    end

    describe "GET edit" do
      before { Comment.create!(post: first_post, body: "First!", approved: true) }

      it "prefills values" do
        edit_form(first_post)

        expect(json).to include("id" => first_post.id.to_s, "title" => "Edit Post", "display_name" => "Hello world",
          "action" => {"method" => "patch", "path" => "/api/admin/posts/#{first_post.id}"})
        expect(fields["title"]["value"]).to eq("Hello world")
        expect(fields["status"]["value"]).to eq("published")
        expect(fields["featured"]["value"]).to be(true)
        expect(fields["published_at"]["value"]).to eq("2026-01-05T12:00:00Z")
        expect(fields["author"]["value"]).to eq(alice.id.to_s)
        expect(fields["category"]["value"]).to eq(news.id.to_s)
      end

      it "returns json columns as structured values" do
        edit_form(first_post)

        expect(fields["metadata"]["value"]).to eq("seo" => {"slug" => "hello"})
      end

      it "lists existing has_many rows with ids and destroyability" do
        edit_form(first_post)
        comment = first_post.comments.first

        row = sections.last["records"].first
        expect(row).to include("id" => comment.id.to_s, "destroy" => true, "param" => "post[comments_attributes][0]")
        expect(row["fields"].pluck("name", "value")).to include(["body", "First!"], ["approved", true], ["id", comment.id.to_s])
        expect(row["fields"].find { it["name"] == "id" }).to include("control" => "hidden", "param" => "post[comments_attributes][0][id]")
      end

      it "describes tag checkboxes with the ids of the current tags" do
        edit_form(first_post)

        expect(fields["tags"]).to include("control" => "checkboxes", "multiple" => true, "param" => "post[tag_ids][]", "value" => [ruby.id.to_s])
        expect(fields["tags"]["options"]).to eq([{"label" => "ruby", "value" => ruby.id.to_s}])
      end

      it "is a 404 for a missing record" do
        api_get("/api/admin/posts/0/edit")

        expect(response).to have_http_status(:not_found)
      end
    end

    it "describes has_one forms built with semantic_fields_for" do
      edit_form(alice, resource: "authors", schema: nil)

      expect(fields).to include("name", "email", "rating", "born_on")
      expect(fields["bio"]).to include("param" => "author[profile_attributes][bio]")
      expect(sections.pluck("title")).to include("Profile")
    end

    describe "inputs for: a has_one" do
      around do |example|
        config = ActiveAdmin.application.namespace(:admin).resource_for(Author)
        original = config.page_presenters[:form]
        presenter = ActiveAdmin::PagePresenter.new do |f|
          f.inputs("About", for: :profile) { |profile| profile.input :bio }
        end
        config.set_page_presenter(:form, presenter)
        example.run
      ensure
        config.page_presenters[:form] = original
      end

      it "records the nested fields with params and the record's hidden id" do
        profile = Profile.create!(author: alice, bio: "Hello")
        edit_form(alice, resource: "authors", schema: nil)

        expect(sections.pluck("title")).to eq(["About"])
        expect(fields["bio"]).to include("param" => "author[profile_attributes][bio]", "value" => "Hello")
        expect(fields["id"]).to include("control" => "hidden", "param" => "author[profile_attributes][id]", "value" => profile.id.to_s)
      end
    end

    it "matches the contract for untitled sections" do
      edit_form(alice, resource: "authors", schema: nil)

      expect(json).to match_contract("FormResponse")
    end

    it "derives input types from number and date columns" do
      edit_form(alice, resource: "authors", schema: nil)

      expect(fields["rating"]).to include("control" => "number", "value" => "4.5")
      expect(fields["born_on"]).to include("control" => "date", "value" => "1990-01-02")
      expect(fields["email"]).to include("control" => "email")
    end

    it "builds a default form without a form block" do
      new_form("categories", schema: nil)

      expect(fields["name"]).to include("control" => "text", "param" => "category[name]", "required" => true)
    end

    describe "POST create" do
      it "creates a record and reports where AA would go next" do
        api(:post, "/api/admin/posts", body(title: "Fresh", author_id: alice.id, status: "draft"), schema: "WriteResult")

        post = Post.find_by!(title: "Fresh")
        expect(response).to have_http_status(:created)
        expect(json).to include("ok" => true, "id" => post.id.to_s, "message" => "Post was successfully created.")
        expect(json["location"]).to include("resource" => "posts", "id" => post.id.to_s, "view" => "show", "url" => "/admin/posts/#{post.id}")
        expect(post).to have_attributes(author: alice, status: "draft")
      end

      it "stores structured json values" do
        api(:post, "/api/admin/posts", body(title: "Meta", author_id: alice.id, metadata: {"a" => {"b" => [1, 2]}}))

        expect(Post.find_by!(title: "Meta").metadata).to eq("a" => {"b" => [1, 2]})
      end

      it "assigns has_many through ids" do
        api(:post, "/api/admin/posts", body(title: "Tagged", author_id: alice.id, tag_ids: [ruby.id]))

        expect(Post.find_by!(title: "Tagged").tags).to eq([ruby])
      end

      it "creates nested has_many rows" do
        api(:post, "/api/admin/posts", body(title: "With comments", author_id: alice.id,
          comments_attributes: {"0" => {body: "one"}, "1" => {body: "two", approved: true}}))

        expect(Post.find_by!(title: "With comments").comments.order(:id).pluck(:body, :approved)).to eq([["one", false], ["two", true]])
      end

      it "ignores attributes outside permit_params" do
        api(:post, "/api/admin/posts", body(title: "Sneaky", author_id: alice.id, views_count: 9999))

        expect(Post.find_by!(title: "Sneaky").views_count).to eq(0)
      end

      it "answers 422 with errors keyed by attribute when invalid" do
        expect { api(:post, "/api/admin/posts", body(title: "", author_id: alice.id)) }.not_to change(Post, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to include("code" => "invalid", "errors" => {"title" => ["can't be blank"]}, "base" => [])
      end

      it "reports nested row errors under Rails' keys" do
        api(:post, "/api/admin/posts", body(title: "Bad rows", author_id: alice.id, comments_attributes: {"0" => {body: ""}}))

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["errors"]).to include("comments.body" => ["can't be blank"])
      end

      it "treats a body without the param key as an empty form (AA's permit_params does not require it)" do
        expect { api(:post, "/api/admin/posts", {}) }.not_to change(Post, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["errors"]).to include("title" => ["can't be blank"])
      end
    end

    describe "PATCH update (controller override with `render :edit`)" do
      it "reports the override's flash as the message" do
        api(:patch, "/api/admin/posts/#{first_post.id}", body(title: "Renamed").merge(lock: lock_of(first_post)), schema: "WriteResult")

        expect(response).to have_http_status(:ok)
        expect(json).to include("ok" => true, "id" => first_post.id.to_s, "message" => "Post saved")
        expect(first_post.reload.title).to eq("Renamed")
      end

      it "turns a re-rendered edit form into 422 with the record's errors" do
        api(:patch, "/api/admin/posts/#{first_post.id}", body(title: "").merge(lock: lock_of(first_post)))

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to include("code" => "invalid", "errors" => {"title" => ["can't be blank"]})
        expect(first_post.reload.title).to eq("Hello world")
      end

      it "updates and removes nested has_many rows" do
        comment = Comment.create!(post: first_post, body: "old")
        api(:patch, "/api/admin/posts/#{first_post.id}", body(comments_attributes: {"0" => {id: comment.id, _destroy: "1"}, "1" => {body: "new"}}).merge(lock: lock_of(first_post)))

        expect(first_post.comments.reload.pluck(:body)).to eq(["new"])
      end

      it "writes the json column" do
        api(:patch, "/api/admin/posts/#{first_post.id}", body(metadata: {"seo" => nil}).merge(lock: lock_of(first_post)))

        expect(first_post.reload.metadata).to eq("seo" => nil)
      end
    end

    describe "PATCH update (AA's own responder)" do
      it "reports AA's flash notice and the redirect" do
        api(:patch, "/api/admin/authors/#{alice.id}", body({name: "Alicia"}, key: "author").merge(lock: lock_of(alice)), schema: "WriteResult")

        expect(json).to include("ok" => true, "message" => "Author was successfully updated.")
        expect(json["location"]).to include("resource" => "authors", "id" => alice.id.to_s, "view" => "show")
        expect(alice.reload.name).to eq("Alicia")
      end

      it "answers 422 when AA re-renders the form" do
        api(:patch, "/api/admin/authors/#{alice.id}", body({name: ""}, key: "author").merge(lock: lock_of(alice)))

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["errors"]).to eq("name" => ["can't be blank"])
      end
    end

    describe "DELETE destroy" do
      it "destroys when the adapter allows it" do
        api(:delete, "/api/admin/posts/#{second_post.id}", schema: "WriteResult")

        if can_destroy_post?(admin)
          expect(json).to include("ok" => true, "id" => second_post.id.to_s)
          expect(json["location"]).to include("resource" => "posts", "view" => "index")
          expect(Post.exists?(second_post.id)).to be(false)
        else
          expect(response).to have_http_status(:forbidden)
          expect(json).to include("code" => "forbidden")
          expect(Post.exists?(second_post.id)).to be(true)
        end
      end

      it "destroys records of other resources regardless" do
        api(:delete, "/api/admin/tags/#{ruby.id}")

        expect(response).to have_http_status(:ok)
        expect(Tag.exists?(ruby.id)).to be(false)
      end

      it "is a 404 for a missing record" do
        api(:delete, "/api/admin/tags/0")

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  context "when signed in as an editor" do
    before { sign_in editor }

    it "refuses to update a record the adapter hides" do
      api(:patch, "/api/admin/posts/#{second_post.id}", body(title: "Hijack").merge(lock: lock_of(second_post)))

      expect(response).to have_http_status(can_see_post?(editor, second_post) ? :ok : :forbidden)
      expect(second_post.reload.title).to eq(can_see_post?(editor, second_post) ? "Hijack" : "Bob's draft")
    end

    it "updates a record it owns" do
      api(:patch, "/api/admin/posts/#{first_post.id}", body(title: "Mine").merge(lock: lock_of(first_post)))

      expect(response).to have_http_status(:ok)
      expect(first_post.reload.title).to eq("Mine")
    end

    it "applies the adapter to destroy" do
      api(:delete, "/api/admin/posts/#{first_post.id}")

      expect(response).to have_http_status(can_destroy_post?(editor) ? :ok : :forbidden)
    end

    it "refuses forms of resources the adapter hides" do
      api_get("/api/admin/categories/new")

      expect(response).to have_http_status(can_read_categories?(editor) ? :ok : :forbidden)
    end
  end

  context "when signed out" do
    it "answers 401 for forms and writes" do
      api_get("/api/admin/posts/new")
      expect(response).to have_http_status(:unauthorized)

      api(:post, "/api/admin/posts", body(title: "x", author_id: alice.id))
      expect(response).to have_http_status(:unauthorized)
      expect(Post.where(title: "x")).to be_empty
    end
  end
end
