RSpec.describe "menu overlay", type: :request do
  include_context "with a blog"

  let(:menu) { api_get("/api/admin/_manifest", schema: "Manifest")["menu"] }

  def find_item(items, id) = items.lazy.filter_map { |item| (item["id"] == id) ? item : find_item(item["children"], id) }.first

  def ids(items) = items.flat_map { [it["id"], *ids(it["children"])] }

  around do |example|
    ReactiveAdmin::MenuOverlay.reset!
    example.run
  ensure
    ReactiveAdmin::MenuOverlay.reset!
  end

  before { sign_in admin }

  it "places resources in groups above AA's own parents" do
    ReactiveAdmin.menu do
      group "Setup", priority: 90 do
        group "Taxonomy" do
          resources :categories, :tags
        end
        link "Status", url: "https://status.example.com"
      end
    end

    setup = find_item(menu, "setup")
    expect(setup).to include("label" => "Setup", "priority" => 90)
    expect(find_item(setup["children"], "setup/taxonomy")["children"].pluck("resource")).to eq(%w[categories tags])
    expect(find_item(setup["children"], "setup/status")).to include("url" => "https://status.example.com")
  end

  it "moves resources rather than copying them" do
    ReactiveAdmin.menu { group("Setup") { resources :tags } }

    expect(ids(menu).count("tags")).to eq(1)
    expect(find_item(find_item(menu, "content")["children"], "tags")).to be_nil
  end

  it "leaves resources the overlay does not mention where AA put them" do
    ReactiveAdmin.menu { group("Setup") { resources :tags } }

    expect(find_item(find_item(menu, "content")["children"], "posts")).to be_present
  end

  it "replaces an AA menu link the overlay redeclares" do
    ReactiveAdmin.menu { link "Docs", url: "https://example.com/docs" }

    expect(ids(menu).count("docs")).to eq(1)
  end

  it "evaluates link conditions for the current user" do
    ReactiveAdmin.menu do
      group "Setup" do
        link "Admins", url: "/admins", if: -> { current_active_admin_user.role == "admin" }
        link "Editors", url: "/editors", if: -> { current_active_admin_user.role == "editor" }
      end
    end

    expect(find_item(menu, "setup")["children"].pluck("label")).to eq(["Admins"])
  end

  it "drops groups whose items the user may not see" do
    ReactiveAdmin.menu { group("Hidden") { link "Nope", url: "/x", if: -> { false } } }

    expect(ids(menu)).not_to include("hidden")
  end

  describe "hide" do
    def audit_keys(kind) = ReactiveAdmin::MenuOverlay.audit.select { it[:kind] == kind }.pluck(:key)

    it "leaves resources and pages out of the menu without reporting them as unplaced" do
      ReactiveAdmin.menu do
        group("Setup") { resources :categories }
        hide :tags
      end
      menu

      expect(ids(menu)).not_to include("tags")
      expect(ids(menu)).to include("posts")
      expect(audit_keys(:menu_unplaced)).not_to include("tags")
      expect(audit_keys(:menu_unplaced)).to include("posts")
    end

    it "does not report a `menu false` page nested under a parent as unplaced" do
      ReactiveAdmin.menu { hide :tags }
      menu

      expect(audit_keys(:menu_unplaced)).not_to include("post_digests")
      expect(ids(menu)).not_to include("post_digests")
    end

    it "works inside a group" do
      ReactiveAdmin.menu do
        group "Setup" do
          resources :categories
          hide :tags
        end
      end

      expect(ids(menu)).not_to include("tags")
      expect(audit_keys(:menu_unknown)).to be_empty
    end

    it "reports a key that matches nothing registered" do
      ReactiveAdmin.menu { hide :tags, :nope }

      expect(ReactiveAdmin::MenuOverlay.audit).to include({kind: :menu_unknown, item: "hide", key: "nope"})
      expect(audit_keys(:menu_unknown)).to eq(["nope"])
    end

    it "does not place the key, so exposure sees it as unlisted" do
      ReactiveAdmin.menu { hide :tags }

      expect(ReactiveAdmin::MenuOverlay.keys(:resource)).to be_empty
    end
  end

  describe "resources and pages AA keeps out of its menu (`menu false`)" do
    def audit_keys(kind) = ReactiveAdmin::MenuOverlay.audit.select { it[:kind] == kind }.pluck(:key)

    def classic_ids = ActiveAdmin.application.namespace(:admin).fetch_menu(:default).items.flat_map { [it.id, *it.items.map(&:id)] }

    it "shows a placed resource, a placed page and the comments resource in the React menu only" do
      ReactiveAdmin.menu {
        group("Setup") {
          resources :notes, :admin_comments
          page :post_previews
        }
      }

      children = find_item(menu, "setup")["children"]
      expect(children.pluck("kind", "resource", "page").map(&:compact)).to include(%w[resource notes], %w[resource admin_comments], %w[page post_previews])
      expect(find_item(children, "notes")).to include("label" => "Notes", "kind" => "resource", "resource" => "notes")
      expect(classic_ids).not_to include("notes", "admin_comments", "post_previews")
      expect(audit_keys(:menu_hidden)).to be_empty
    end

    it "leaves them out of the menu unless placed" do
      ReactiveAdmin.menu { group("Setup") { resources :tags } }

      expect(ids(menu)).not_to include("notes", "admin_comments", "post_previews")
    end

    it "exposes a placed resource under `expose = :listed`" do
      ReactiveAdmin.config.expose = :listed
      ReactiveAdmin.menu { group("Setup") { resources :notes } }

      expect(find_item(menu, "notes")).to be_present
      expect(api_get("/api/admin/notes")).to be_present
    ensure
      ReactiveAdmin.config.expose = :all
    end

    it "reports placed keys that stay hidden for other reasons" do
      ReactiveAdmin.config.expose = :listed
      ReactiveAdmin::Registry.find("notes").reactive_options[:expose] = false
      ReactiveAdmin.menu {
        group("Setup") {
          resources :notes
          page :post_digests
        }
      }

      expect(audit_keys(:menu_hidden)).to match_array(%w[notes post_digests])
      expect(ids(menu)).not_to include("notes", "post_digests")
    ensure
      ReactiveAdmin.config.expose = :all
      ReactiveAdmin::Registry.find("notes").reactive_options.delete(:expose)
    end
  end

  it "refuses menus deeper than three levels" do
    expect do
      ReactiveAdmin.menu { group("A") { group("B") { group("C") { resources :tags } } } }
    end.to raise_error(ReactiveAdmin::MenuOverlay::DepthError, /maximum is 3/)
  end

  it "honours `reactive { menu path: }` hints on resources" do
    config = ReactiveAdmin::Registry.find("tags")
    config.reactive_options[:menu] = {path: ["Hinted"]}
    ReactiveAdmin::MenuOverlay.reset!

    expect(find_item(find_item(menu, "hinted")["children"], "tags")).to be_present
  ensure
    config.reactive_options.delete(:menu)
  end
end
