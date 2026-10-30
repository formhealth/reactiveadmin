# Cross-endpoint checks that the API tells the same story as the adapter, whichever one runs.
RSpec.describe "authorization", type: :request do
  include_context "with a blog"

  let(:users) { {"admin" => admin, "editor" => editor} }

  def visible_ids(user) = [first_post, second_post, third_post].select { can_see_post?(user, it) }.map { it.id.to_s }

  describe "scoping" do
    %w[admin editor].each do |role|
      context "as #{role}" do
        let(:user) { users.fetch(role) }

        before { sign_in user }

        it "limits index rows, counts and scope counts to the same set" do
          api_get("/api/admin/posts", schema: "IndexResponse")

          expect(json["rows"].pluck("id")).to match_array(visible_ids(user))
          expect(json["meta"]["total_count"]).to eq(visible_ids(user).size)
        end

        it "limits csv to the same set" do
          api_get("/api/admin/posts.csv")

          ids = CSV.parse(response.body.delete_prefix("﻿"), headers: true)["Id"]
          expect(ids).to match_array(visible_ids(user))
        end

        it "limits show to the same set" do
          [first_post, second_post, third_post].each do |post|
            api_get("/api/admin/posts/#{post.id}")

            expect(response).to have_http_status(can_see_post?(user, post) ? :ok : :forbidden), "post #{post.id}"
          end
        end

        it "limits typeahead options to the same set" do
          api_get("/api/admin/comments/_options", field: "post", context: "filter")

          expect(json["options"].pluck("value")).to match_array(visible_ids(user))
        end
      end
    end
  end

  describe "permission flags do not lie" do
    %w[admin editor].each do |role|
      context "as #{role}" do
        let(:user) { users.fetch(role) }

        before { sign_in user }

        it "lets every row's update flag predict whether a PATCH succeeds" do
          api_get("/api/admin/posts")

          json["rows"].each do |row|
            api(:patch, row["paths"]["api_show"], {post: {title: "Same"}, lock: lock_of(Post.find(row["id"]))})

            expect(response).to have_http_status(row["permissions"]["update"] ? :ok : :forbidden), "post #{row["id"]}"
          end
        end

        it "lets every row's destroy flag predict whether a DELETE succeeds" do
          api_get("/api/admin/posts")

          json["rows"].each do |row|
            api(:delete, row["paths"]["api_show"])

            expect(response).to have_http_status(row["permissions"]["destroy"] ? :ok : :forbidden), "post #{row["id"]}"
          end
        end

        it "lets the show page's flags and actions agree with the adapter" do
          post = Post.where(id: visible_ids(user)).first
          api_get("/api/admin/posts/#{post.id}")

          expect(json["permissions"]).to eq("show" => true, "update" => true, "destroy" => can_destroy_post?(user))
          expect(by_key(json["actions"])["destroy"]["enabled"]).to eq(can_destroy_post?(user))
        end

        it "lets the manifest's resource flags agree with the form endpoints" do
          api_get("/api/admin/_manifest")
          posts = by_key(json["resources"])["posts"]

          api_get("/api/admin/posts/new")
          expect(response).to have_http_status(posts["permissions"]["create"] ? :ok : :forbidden)
        end

        it "lists exactly the resources whose index answers 200" do
          api_get("/api/admin/_manifest")
          listed = json["resources"].pluck("key")

          %w[posts categories tags authors].each do |key|
            api_get("/api/admin/#{key}")

            expect(listed.include?(key)).to eq(response.status == 200), key
          end
        end
      end
    end
  end

  describe "who gets which action items" do
    it "evaluates `if:` per user on show pages" do
      sign_in admin
      api_get("/api/admin/posts/#{second_post.id}")
      expect(by_key(json["actions"])).to have_key("publish")

      sign_in editor
      api_get("/api/admin/posts/#{third_post.id}")
      expect(by_key(json["actions"])).to have_key("publish")
    end
  end
end
