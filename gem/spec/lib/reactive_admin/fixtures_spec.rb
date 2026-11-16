require "rake"

SEED = "spec-seed"

RSpec.describe ReactiveAdmin::Fixtures do
  leak = "ZQXLEAK"

  let!(:admin) { create_admin(name: "#{leak} Admin", email: "admin-#{leak.downcase}@leak.test") }
  let!(:author) { create_author(name: "#{leak} Alice", email: "alice-#{leak.downcase}@leak.test", rating: 4.5, born_on: Date.new(1990, 1, 2)) }
  let!(:category) { Category.create!(name: "#{leak} News", api_token: "#{leak}-token-123", settings: {"#{leak}key" => "#{leak} value"}) }
  let!(:tag) { Tag.create!(name: "#{leak} tag") }
  let!(:post) do
    create_post(author:, title: "#{leak} Hello world", body: "#{leak} body text.\nSecond #{leak} line.", status: :published,
      published_at: Time.zone.local(2026, 1, 5, 12), views_count: 1234, category:, tags: [tag],
      metadata: {"slug" => "#{leak.downcase}-slug", "contact@#{leak.downcase}.test" => ["#{leak} nested", 42], "#{leak.downcase}_positive" => true})
  end
  let!(:comment) { post.comments.create!(body: "#{leak} comment", context: {"note" => "#{leak} context"}) }
  let(:originals) { [admin.name, admin.email, author.name, author.email, category.name, category.api_token, tag.name, post.title, post.body, post.metadata.to_json, comment.body] }

  before { allow(ReactiveAdmin.config).to receive(:doctor_user).and_return(-> { admin }) }

  def record(**) = described_class.record(**)

  def text(result) = result.files.values.map { JSON.generate(it) }.join("\n")

  describe ".record" do
    subject(:result) { record }

    it "writes the manifest and, per resource, meta, index, show and the forms" do
      expect(result.files.keys).to include("_manifest.json", "posts/meta.json", "posts/index.json", "posts/show.json", "posts/new.json", "posts/edit.json")
    end

    it "validates every file against the contract" do
      schemas = {"meta.json" => "ResourceMeta", "index.json" => "IndexResponse", "show.json" => "ShowResponse", "new.json" => "FormResponse", "edit.json" => "FormResponse"}
      result.files.each do |path, payload|
        expect(payload).to match_contract((path == "_manifest.json") ? "Manifest" : schemas.fetch(File.basename(path))), path
      end
    end

    it "keeps no value of any record, in keys, values, paths or forms" do
      output = text(result)

      expect(output).not_to include(leak)
      expect(output.downcase).not_to include(leak.downcase)
      originals.each { expect(output).not_to include(JSON.generate(it)[1..-2]) }
    end

    it "keeps the structure the client reads" do
      index = result.files["posts/index.json"]

      expect(index["columns"].pluck("key")).to include("title", "status", "published_at")
      expect(index["rows"].first["cells"].keys).to eq(index["columns"].pluck("key"))
      expect(result.files["posts/edit.json"]["form"]["sections"].flat_map { it["fields"] }.pluck("control")).to include("text", "select", "typeahead", "json")
    end

    it "keeps enum names and the labels the host wrote" do
      status = result.files["posts/edit.json"]["form"]["sections"].first["fields"].find { it["name"] == "status" }

      expect(status).to include("value" => "published", "label" => "Status")
      expect(status["options"].pluck("value")).to eq(%w[draft published archived])
    end

    it "replaces ids consistently across files and keeps them out of paths" do
      id = result.files["posts/index.json"]["rows"].first["id"]
      files = result.files.slice("posts/show.json", "posts/edit.json").values

      expect(id).not_to eq(post.id.to_s)
      expect(files.pluck("id")).to eq([id, id])
      expect(result.files["posts/index.json"]["rows"].first["paths"]["api_show"]).to eq("/api/admin/posts/#{id}")
      expect(result.files["_manifest.json"].dig("site", "current_user", "id")).not_to eq(admin.id.to_s)
    end

    it "agrees on the fake of a record that two resources show" do
      author_ref = result.files["posts/index.json"]["rows"].first.dig("cells", "author", "ref", "id")
      author_row = result.files["authors/index.json"]["rows"].find { it["id"] == author_ref }

      expect(author_row).to be_present
      expect(author_row["display_name"]).to eq(result.files["posts/index.json"]["rows"].first.dig("cells", "author", "label"))
    end

    it "keeps masked values masked, with no value behind them" do
      field = result.files["categories/edit.json"]["form"]["sections"].flat_map { it["fields"] }.find { it["name"] == "api_token" }

      expect(field).to include("masked" => true)
      expect(field).not_to have_key("value")
    end

    it "keeps the shape of dates, numbers, and json" do
      form = result.files["posts/edit.json"]["form"]["sections"].flat_map { it["fields"] }.index_by { it["name"] }

      expect(form["published_at"]["value"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
      expect(form["published_at"]["value"]).not_to eq("2026-01-05T12:00:00Z")
      expect(form["metadata"]["value"].size).to eq(post.metadata.size)
      expect(form["metadata"]["value"].keys).not_to include("slug")
      expect(form["metadata"]["value"].values.flatten.map(&:class)).to include(String, Integer)
      expect(form["featured"]["value"]).to be(false).or be(true)
    end

    it "is the same every time, so a diff shows only what changed in the app" do
      expect(record.files).to eq(result.files)
    end

    it "limits itself to the resources asked for" do
      expect(record(resources: %w[tags]).files.keys.map { it.split("/").first }.uniq).to eq(%w[_manifest.json tags])
    end

    it "samples a session-only action as the session it renders in" do
      declare_guard("posts", :session_only, only: [:index], reason: "Admin only")

      expect(record(resources: %w[posts]).files).to include("posts/index.json")
    end

    it "says what it left out and why, without values" do
      skipped = result.skipped.to_h { |key, section, reason| [[key, section], reason] }

      expect(skipped.values).to all(be_a(String))
      expect(skipped.to_s).not_to include(leak)
    end

    it "refuses an unknown resource, and a missing sampling user" do
      expect { record(resources: %w[nope]) }.to raise_error(described_class::Error, /unknown resources: nope/)
      allow(ReactiveAdmin.config).to receive(:doctor_user).and_return(nil)
      expect { record }.to raise_error(described_class::Error, /doctor_user/)
    end
  end

  describe "rake reactiveadmin:fixtures" do
    let(:task) { Rake::Task["reactiveadmin:fixtures"] }
    let(:dir) { Rails.root.join("tmp/fixtures_spec") }

    before do
      Rails.application.load_tasks unless Rake::Task.task_defined?("reactiveadmin:fixtures")
      task.reenable
    end

    after { FileUtils.rm_rf(dir) }

    it "writes JSON files for the chosen resources to the directory" do
      expect { task.invoke("posts+tags", "tmp/fixtures_spec") }.to output(/wrote \d+ files to tmp\/fixtures_spec.*warning: kept \d+ host-written strings verbatim.*\n  "Title"\n/m).to_stdout

      files = Dir[dir.join("**/*.json")].map { it.delete_prefix("#{dir}/") }
      expect(files).to include("_manifest.json", "posts/index.json", "tags/index.json")
      expect(files.grep(/\Aauthors/)).to be_empty
      expect(JSON.parse(File.read(dir.join("posts/show.json")))).to include("resource" => "posts")
      expect(Dir[dir.join("**/*")].sum { File.file?(it) ? File.read(it).scan(leak).size : 0 }).to eq(0)
    end

    it "removes leftovers of the sections it now skips, and leaves other resources alone" do
      stale = %w[tags/show.json tags/edit.json]
      (stale + %w[authors/show.json]).each do |file|
        FileUtils.mkdir_p(dir.join(File.dirname(file)))
        File.write(dir.join(file), %({"title":"#{leak}"}))
      end
      Tag.destroy_all

      expect { task.invoke("tags", "tmp/fixtures_spec") }.to output(/skipped tags show: no records/).to_stdout

      expect(stale.map { dir.join(it).exist? }).to eq([false, false])
      expect(dir.join("tags/index.json")).to exist
      expect(dir.join("authors/show.json")).to exist
    end

    it "aborts with the reason when it can't run" do
      allow(ReactiveAdmin.config).to receive(:doctor_user).and_return(nil)

      expect { task.invoke }.to raise_error(SystemExit).and output(/doctor_user/).to_stderr
    end
  end

  describe ReactiveAdmin::Fixtures::Scrubber do
    subject(:scrubber) { described_class.new(seed: SEED, vocabulary: {"posts" => {"status" => %w[draft]}}) }

    def scrub(kind, payload) = scrubber.scrub_all([[kind, payload, "posts"]]).first

    it "replaces a string under a key it doesn't know" do
      expect(scrub(:show, {"surprise" => "Jane Doe", "type" => "text"})).to match("surprise" => a_string_matching(/\A\p{Upper}\p{Lower}+ \p{Upper}\p{Lower}+\z/), "type" => "text")
    end

    it "keeps vocabulary and masked nodes, and shapes emails, urls, uuids and numbers" do
      node = scrub(:show, {"rows" => [{"type" => "masked"}, {"cells" => {"status" => {"type" => "status", "label" => "Draft"}}}, {"type" => "text", "text" => "a@b.co"},
        {"type" => "text", "text" => "https://x.test/y"}, {"type" => "text", "text" => "3f2a9c1e-0000-4000-8000-000000000000"}, {"type" => "text", "text" => "1,234.50"}]})

      expect(node["rows"].map { it["text"] || it["label"] || it.dig("cells", "status", "label") }).to match([nil, "Draft", /\Auser\d{5}@example\.com\z/, %r{\Ahttps://example\.com/}, /\A\h{8}-\h{4}-4\h{3}-a\h{3}-\h{12}\z/, /\A\d,\d{3}\.\d{2}\z/])
      expect(node["rows"].first).to eq("type" => "masked")
    end

    it "drops host-written text that quotes a replaced value" do
      payload = {"title" => "Hello", "layout" => [{"type" => "text", "text" => "Jane Doe"}, {"label" => "Archive Jane Doe?", "key" => "archive"}, {"label" => "Archive", "key" => "x"}]}

      labels = scrub(:show, payload)["layout"].filter_map { it["label"] }
      expect(labels.first).not_to include("Jane")
      expect(labels.last).to eq("Archive")
    end

    it "scrubs the text and attributes of html, keeping the tags" do
      html = scrub(:show, {"type" => "html", "html" => %(<p class="note">Secret <a href="https://leak.test/u" title="Jane">Jane Doe</a></p>)})["html"]

      expect(html).to match(%r{\A<p class="note">\w+ <a href="https://example\.com/[^"]+" title="\w+">\w+ \w+</a></p>\z})
    end

    it "replaces every json key, keeping the structure" do
      value = scrub(:show, {"type" => "json", "value" => {"allergies" => {"penicillin" => true}, "hiv_positive" => true, "jane@doe.test" => 1, "Jane" => [2.5]}})

      expect(JSON.generate(value)).not_to match(/allerg|penicillin|hiv|jane/i)
      expect(value["value"].size).to eq(4)
      expect(value["value"].values.flatten.map(&:class)).to include(Hash, TrueClass, Integer, Float)
    end

    it "replaces the keys of a json summary with the fakes of the value's keys" do
      summary = scrub(:show, {"type" => "json", "summary" => {"keys" => %w[hiv_positive], "size" => 1}, "value" => {"hiv_positive" => true}})

      expect(summary["summary"]["keys"]).to eq(summary["value"].keys)
      expect(JSON.generate(summary)).not_to include("hiv")
    end

    it "never gives two json keys the same fake" do
      keys = (1..2000).map { "user#{it}@example.test" }
      value = scrub(:show, {"type" => "json", "value" => keys.index_with(1)})["value"]

      expect(value.size).to eq(keys.size)
    end

    describe "leaks" do
      def scrub_with(payloads, **) = described_class.new(seed: SEED, **).scrub_all(payloads.map { [:show, it, "posts"] })

      def field(name, value, **extra) = {"control" => "select", "name" => name, "param" => "x[#{name}]", "value" => value, **extra}

      it "scrubs a record value that the host's own text repeats" do
        payload = {"id" => "5", "resource" => "authors", "display_name" => "ZQXLEAK Doe",
                   "layout" => [{"type" => "panel", "title" => "ZQXLEAK Doe", "label" => "About ZQXLEAK Doe", "children" => []}]}

        expect(JSON.generate(scrub(:show, payload))).not_to include("ZQXLEAK")
      end

      it "gives an option the id mapping unless label and value are both vocabulary" do
        rows = {"rows" => [{"id" => "73941", "display_name" => "Published"}]}
        select = field("author_id", "73941", "options" => [{"label" => "Published", "value" => "73941"}, {"label" => "Draft", "value" => "draft"}])

        index, form = scrub_with([rows, select], vocabulary: {"posts" => {"author_id" => %w[draft published]}})
        option = form["options"].first

        expect(option["value"]).to eq(index["rows"].first["id"]).and eq(form["value"])
        expect(option["value"]).not_to eq("73941")
        expect(form["options"].last["value"]).to eq("draft")
      end

      it "scrubs option hints as data" do
        select = field("author_id", "5", "options" => [{"label" => "ZQXLEAK Doe", "value" => "5", "hint" => "zqxleak@leak.test"}])

        output = JSON.generate(scrub(:form, select))

        expect(output).not_to match(/zqxleak/i)
        expect(output).to include("@example.com")
      end

      it "keeps admin route segments and scrubs the opaque ones in relative paths" do
        scrubber = described_class.new(seed: SEED, routes: %w[rails active_storage blobs redirect admin posts edit])
        nodes = [{"type" => "image", "src" => "/rails/active_storage/blobs/redirect/ZQXLEAKtoken123/ZQXLEAK-report.pdf?disposition=ZQXLEAK"},
          {"type" => "html", "html" => %(<p>x</p><a href="/files/ZQXLEAK/ZQXLEAK%20Doe.pdf">x</a><img src="/ZQXLEAK.png">)},
          {"type" => "link", "href" => "/admin/posts/ZQXLEAK-slug/edit#ZQXLEAK"}]

        image, html, link = scrubber.scrub_all([[:show, {"layout" => nodes}]]).first["layout"]

        expect(JSON.generate([image, html, link])).not_to match(/zqxleak/i)
        expect(image["src"]).to match(%r{\A/rails/active_storage/blobs/redirect/[\w-]+/[\w-]+\.pdf\?disposition=\w+\z})
        expect(link["href"]).to match(%r{\A/admin/posts/[\w-]+/edit#[\w-]+\z})
      end

      it "gives a hidden nested id the mapping of the record's other ids" do
        form = {"form" => {"sections" => [{"fields" => [{"name" => "id", "param" => "post[comments_attributes][0][id]", "label" => "Id", "control" => "hidden", "value" => "7"}]}]}}
        row = {"rows" => [{"id" => "7", "display_name" => "ZQXLEAK"}], "api_show" => "/api/admin/comments/7"}

        index, edit = scrub_with([row, form], routes: %w[api admin comments])
        hidden = edit.dig("form", "sections", 0, "fields", 0, "value")

        expect(hidden).to eq(index["rows"].first["id"])
        expect(index["api_show"]).to end_with("/#{hidden}")
        expect(hidden).not_to eq("7")
      end

      it "gives the id in an options query the mapping of the record's id" do
        row = {"id" => "1", "display_name" => "ZQXLEAK", "api_edit" => "/api/admin/posts/1/edit"}
        form = {"control" => "typeahead", "name" => "tags", "param" => "post[tag_ids]", "options_path" => "/api/admin/posts/_options?context=form&field=tags&id=1"}

        index, options = scrub_with([row, form], routes: %w[api admin posts edit _options])
        id = index["id"]

        expect(id).not_to eq("1")
        expect(options["options_path"]).to eq("/api/admin/posts/_options?context=form&field=tags&id=#{id}")
        expect(index["api_edit"]).to eq("/api/admin/posts/#{id}/edit")
      end

      it "scrubs the values of an action's hidden params, keeping their names" do
        action = {"key" => "sso", "kind" => "link", "href" => "/auth/sso", "navigate" => true, "params" => {"name" => "ZQXLEAK Doe", "code" => "zqxleak-secret"}}

        scrubbed = scrub(:show, {"actions" => [action]})["actions"].first

        expect(scrubbed["params"].keys).to eq(%w[name code])
        expect(JSON.generate(scrubbed)).not_to match(/zqxleak/i)
      end

      it "keeps the sortable column name of a has_many section" do
        section = {"kind" => "has_many", "name" => "comments", "param_key" => "comments_attributes", "sortable" => "position", "title" => "Comments"}

        expect(scrub(:form, section)["sortable"]).to eq("position")
      end

      it "keeps the marker of a masked json value and scrubs the rest" do
        field = {"control" => "json", "name" => "context", "param" => "x[context]", "value" => {"api_key" => "[masked]", "note" => "ZQXLEAK"}}

        value = scrub(:form, field)["value"]

        expect(value.values).to include("[masked]")
        expect(JSON.generate(value)).not_to match(/zqxleak/i)
      end

      it "keeps the whitespace around inline text, including whitespace-only nodes" do
        nodes = scrub(:show, {"children" => [{"type" => "text", "text" => "ZQXLEAK Doe "}, {"type" => "text", "text" => " and "}, {"type" => "text", "text" => "  "}]})["children"]

        expect(nodes.map { it["text"] }).to match([/\A\p{Alpha}+ \p{Alpha}+ \z/, /\A \p{Alpha}+ \z/, "  "])
        expect(JSON.generate(nodes)).not_to match(/zqxleak/i)
      end

      it "scrubs host text that quotes a number it replaced" do
        field = {"control" => "number", "name" => "account", "param" => "x[account]", "label" => "Account 123456789", "value" => 123456789}

        expect(JSON.generate(scrub(:form, field))).not_to include("123456789")
      end

      it "scrubs host text that quotes an id it replaced" do
        payloads = [{"rows" => [{"id" => "73941", "display_name" => "ZQXLEAK"}]}, {"actions" => [{"key" => "destroy", "confirm" => "Delete author #73941?"}]}]

        expect(JSON.generate(scrub_with(payloads))).not_to include("73941")
      end

      it "keeps the clock format of a time-only value without keeping the time" do
        times = scrub(:form, {"control" => "time", "name" => "starts_at", "param" => "x[starts_at]", "value" => "13:45:07"})["value"]

        expect(times).to match(/\A\d{2}:\d{2}:\d{2}\z/)
        expect(times).not_to eq("13:45:07")
        expect(Time.utc(2000, 1, 1, *times.split(":").map(&:to_i))).to be_a(Time)
      end

      it "replaces an action key derived from a record's name, in every payload" do
        payloads = [{"rows" => [{"id" => "9", "display_name" => "Jane Doe"}]}, {"actions" => [{"key" => "contact_jane_doe", "kind" => "link", "label" => "Contact Jane Doe"}, {"key" => "archive", "kind" => "link", "label" => "Archive"}]}]

        scrubbed = scrub_with(payloads)

        keys = scrubbed.last["actions"].pluck("key")
        expect(keys.first).to match(/\A[a-z]+_\d+\z/)
        expect(keys.last).to eq("archive")
        expect(JSON.generate(scrubbed)).not_to match(/jane/i)
      end

      it "does not read nested json arrays as nodes" do
        value = scrub(:show, {"type" => "json", "value" => [[{"type" => "person", "name" => "Jane Doe"}]]})["value"]

        expect(JSON.generate(value)).not_to match(/person|jane/i)
      end

      it "treats cells as a map of columns, whatever they are called" do
        cells = {"value" => {"type" => "number", "value" => 12}, "params" => {"type" => "text", "text" => "Jane"}}

        scrubbed = scrub(:index, {"rows" => [{"id" => "1", "cells" => cells}]})["rows"].first["cells"]

        expect(scrubbed["value"]).to include("type" => "number", "value" => an_instance_of(Integer))
        expect(scrubbed["params"]).to include("type" => "text")
        expect(scrubbed["params"]["text"]).not_to include("Jane")
      end

      it "keeps only small whole-number bounds, and scrubs dates even when every form agrees" do
        input = ->(min, max) { {"control" => "date", "name" => "seen_on", "param" => "x[seen_on]", "input_html" => {"step" => "any", "min" => min, "max" => max, "data-note" => "Jane Doe"}} }

        edit, new = scrub_with([input.call("1987-03-04", 10), input.call("1987-03-04", "100")]).pluck("input_html")

        expect(edit).to include("step" => "any", "max" => 10, "data-note" => a_string_matching(/\A\p{Alpha}+ \p{Alpha}+\z/))
        expect(new["max"]).to eq("100")
        expect([edit["min"], new["min"]]).to all(match(/\A\d{4}-\d{2}-\d{2}\z/))
        expect([edit["min"], new["min"]]).not_to include("1987-03-04")
      end

      it "keeps a scientific-notation float finite" do
        value = scrub(:show, {"type" => "number", "value" => [1.0e100, 2.5e-7, 1.7976931348623157e308]})["value"]

        expect(value).to all(be_finite)
        expect { JSON.generate(value) }.not_to raise_error
      end

      it "scrubs a short record value that the host's own text repeats, without touching longer words" do
        payloads = [{"rows" => [{"id" => "3", "display_name" => "Amy"}]},
          {"layout" => [{"type" => "panel", "title" => "About Amy", "children" => []}], "actions" => [{"key" => "x", "confirm" => "Delete Amy?"}, {"key" => "y", "confirm" => "Amyloid levels"}]}]

        output = scrub_with(payloads).last

        expect(JSON.generate(output)).not_to match(/\bamy\b/i)
        expect(output["actions"].pluck("confirm").last).to eq("Amyloid levels")
      end

      it "scrubs record text that html turns into titles, headers and labels" do
        nodes = [{"type" => "text", "text" => "JD", "title" => "ZQXLEAK Doe"}, {"type" => "definition_list", "rows" => [{"label" => "ZQXLEAK Doe", "value" => [{"type" => "empty"}]}]},
          {"type" => "table", "headers" => ["ZQXLEAK Doe"], "rows" => []}, {"type" => "document", "src" => "/a.pdf", "mime" => "application/pdf", "title" => "ZQXLEAK Doe"}]

        expect(JSON.generate(scrub(:show, {"layout" => nodes}))).not_to match(/zqxleak/i)
      end

      it "keeps the element structure of html that holds only an email" do
        html = scrub(:show, {"type" => "html", "html" => "<p>alice@example.com</p>"})["html"]

        expect(html).to match(%r{\A<p>user\d{5}@example\.com</p>\z})
      end

      it "gives distinct choices distinct fakes, in the options and the selected value" do
        states = %w[AR GA HI IL IN KS KY LA MA MD ME MI MN MO MS MT NC ND NE NH NJ NM NV NY OH OK OR PA RI SC SD TN TX UT VA VT WA WI WV WY]
        select = field("state", "HI", "options" => states.map { {"label" => it, "value" => it} })

        scrubbed = scrub(:form, select)
        values = scrubbed["options"].pluck("value")

        expect(values.uniq.size).to eq(states.size)
        expect(scrubbed["value"]).to eq(values[states.index("HI")])
      end

      it "scrubs host text that quotes a json key" do
        payload = {"layout" => [{"type" => "json", "value" => {"jane@doe.test" => true}}, {"type" => "panel", "title" => "Contact jane@doe.test", "children" => []}]}

        expect(JSON.generate(scrub(:show, payload))).not_to include("jane@doe.test")
      end

      it "scrubs host text that quotes the text inside a stored html value" do
        payload = {"layout" => [{"type" => "html", "html" => "<p>alice@example.test</p>"}, {"label" => "Contact alice@example.test", "key" => "contact"}]}

        expect(JSON.generate(scrub(:show, payload))).not_to include("alice@example.test")
      end

      it "keeps the date-picker marker of a frame input" do
        html = scrub(:show, {"type" => "frame", "src" => "/x", "html" => %(<input type="text" data-reactiveadmin-widget="date" data-other="Jane">)})["html"]

        expect(html).to include(%(data-reactiveadmin-widget="date"))
        expect(html).not_to include("Jane")
      end

      it "keeps each label pointing at its own control" do
        html = scrub(:show, {"type" => "frame", "src" => "/x", "html" => %(<label for="plan_state">S</label><input id="plan_state"><label for="plan_starts">T</label><input id="plan_starts" list="plan_starts_list"><datalist id="plan_starts_list"></datalist>)})["html"]
        fragment = Nokogiri::HTML5.fragment(html)
        ids = fragment.css("[id]").map { it["id"] }

        expect(ids.uniq.size).to eq(3)
        expect(fragment.css("label").map { it["for"] }).to eq(ids.first(2))
        expect(fragment.at_css("input[list]")["list"]).to eq(ids.last)
        expect(html).not_to include("plan_")
      end

      it "scrubs a row class built from a scrubbed value, even with one sampled row" do
        payload = {"rows" => [{"id" => "5", "class_name" => "customer-alice@example.test", "cells" => {"email" => {"type" => "text", "text" => "alice@example.test"}}}]}
        row = scrub(:index, payload)["rows"].first

        expect(JSON.generate(row)).not_to include("alice")
        expect(scrub(:index, {"rows" => [{"id" => "5", "class_name" => "row-urgent", "cells" => {}}]})["rows"].first["class_name"]).to eq("row-urgent")
      end

      it "keeps a numeric scope id, so the default and current scope still name it" do
        meta = scrub(:meta, {"scopes" => [{"id" => "1", "label" => "First"}, {"id" => "2", "label" => "Second"}], "default_scope" => "1", "current_scope" => "2"})

        expect(meta["scopes"].pluck("id")).to eq(%w[1 2])
        expect(meta.values_at("default_scope", "current_scope")).to eq(%w[1 2])
      end

      it "keeps a field the API names in an options or value path" do
        payload = {"options_path" => "/api/admin/posts/_options?context=form&field=comments.author", "expand_path" => "/api/admin/posts/5/_value?field=metadata"}
        out = scrub(:form, payload)

        expect(out["options_path"]).to include("field=comments.author")
        expect(out["expand_path"]).to include("field=metadata")
      end

      it "keeps a URL that holds an email a URL" do
        value = scrub(:show, {"type" => "text", "text" => "https://example.test/?email=alice@company.test"})["text"]

        expect(value).to start_with("https://example.com/")
        expect(value).not_to include("alice")
      end

      it "takes a relative url that ends in a query separator" do
        expect(scrub(:show, {"type" => "link", "href" => "/admin/posts?page=2&&"})["href"]).to end_with("page=2&&")
      end

      it "gives an integer hidden id the mapping of the record's id" do
        form = {"form" => {"sections" => [{"fields" => [{"name" => "id", "param" => "post[id]", "label" => "Id", "control" => "hidden", "value" => 73941}]}]}}
        index, edit = scrub_with([{"rows" => [{"id" => "73941"}]}, form])
        hidden = edit.dig("form", "sections", 0, "fields", 0, "value")

        expect(hidden).to be_a(Integer)
        expect(hidden.to_s).to eq(index["rows"].first["id"])
        expect(hidden).not_to eq(73941)
      end

      it "drops comments from scrubbed html, including html stored in json" do
        out = scrub(:show, {"layout" => [{"type" => "html", "html" => "<p>hello</p><!-- customer@example.test -->"}, {"type" => "json", "value" => {"note" => "<p>hi</p><!-- other@example.test -->"}}]})

        expect(JSON.generate(out)).not_to match(/customer@|other@|<!--/)
      end

      it "keeps a frame form's transport and scrubs its action like a link" do
        get = %(<form method="get" action="/admin/posts?q=Jane"><button formmethod="get">Go</button></form>)
        post = %(<form method="post" action="/admin/posts/5" enctype="multipart/form-data"><input type="hidden" name="_method" value="patch"><button formaction="/admin/posts/5/x" formenctype="text/plain">Save</button></form>)
        get_html, post_html = scrub_with([get, post].map { {"type" => "frame", "src" => "/x", "html" => it} }, routes: %w[admin posts x]).pluck("html")

        expect(get_html).to include(%(method="get"), %(formmethod="get"), %(action="/admin/posts?q=))
        expect(post_html).to include(%(method="post"), %(enctype="multipart/form-data"), %(value="patch"), %(formenctype="text/plain"), %(formaction="/admin/posts/))
        expect(get_html + post_html).not_to include("Jane")
      end

      it "scrubs row actions whose keys come from their labels" do
        rows = [{"id" => "1", "actions" => [{"key" => "call_bob", "kind" => "member", "label" => "Call Bob"}]},
          {"id" => "2", "actions" => [{"key" => "call_ann", "kind" => "member", "label" => "Call Ann"}]}]

        expect(JSON.generate(scrub(:index, {"rows" => rows}))).not_to match(/bob|ann/i)
      end

      it "learns the attributes it fakes, so host text quoting them is scrubbed" do
        payload = {"layout" => [{"type" => "html", "html" => %(<input title="alice@example.test">)}, {"type" => "panel", "title" => "Contact alice@example.test", "children" => []}]}

        expect(JSON.generate(scrub(:show, payload))).not_to include("alice@example.test")
      end

      it "takes an options path whose query it can't decode" do
        expect { scrub(:form, {"options_path" => "/api/admin/posts/_options?q=%&field=title"}) }.not_to raise_error
      end

      it "fakes every attribute of html stored in json, keeping only its tags" do
        value = scrub(:show, {"type" => "json", "value" => {"body" => %(<p class="patient-zqxleak" style="color: red" data-x="zqxleak"><input name="zqxleak_code">hi</p>)}})
        html = value["value"].values.first

        expect(html).not_to match(/zqxleak|color: red/i)
        expect(Nokogiri::HTML5.fragment(html).css("p > input").size).to eq(1)
      end

      it "keeps the host's own markup in an html node" do
        html = scrub(:show, {"type" => "html", "html" => %(<p class="note" style="color: red">hi</p>)})["html"]

        expect(html).to start_with(%(<p class="note" style="color: red">))
      end

      it "maps 20,000 numeric ids without running out of fakes" do
        ids = (1..20_000).map(&:to_s)
        rows = Timeout.timeout(60) { scrub(:index, {"rows" => ids.map { {"id" => it} }})["rows"].pluck("id") }

        expect(rows.uniq.size).to eq(ids.size)
      end

      it "fakes a date field's bounds in order and its value inside them" do
        field = {"control" => "date", "name" => "on", "param" => "x[on]", "value" => "2026-10-15", "input_html" => {"min" => "2026-10-10", "max" => "2026-10-22"}}
        out = scrub(:form, field)
        min, max = out["input_html"].values_at("min", "max").map { Date.iso8601(it) }

        expect(min).to be <= max
        expect(Date.iso8601(out["value"])).to be_between(min, max)
        expect(out["input_html"].values_at("min", "max")).not_to include("2026-10-10", "2026-10-22")
      end

      it "scrubs host text that quotes a form's lock timestamp" do
        payload = {"form" => {"lock" => {"field" => "updated_at", "value" => "2026-03-04T05:06:07Z~abc123"}, "submit_confirm" => "Saved at 2026-03-04T05:06:07Z, overwrite?"}}

        expect(JSON.generate(scrub(:form, payload))).not_to include("2026-03-04T05:06:07")
      end

      it "scrubs host text that quotes a file name or url it replaced" do
        payload = {"layout" => [{"type" => "image", "src" => "/files/alice@example.test.pdf"}, {"type" => "link", "href" => "https://leak.test/docs/report-zqxleak"},
          {"label" => "Attachment alice@example.test.pdf", "key" => "a"}, {"label" => "Open https://leak.test/docs/report-zqxleak", "key" => "b"}, {"label" => "See report-zqxleak", "key" => "c"}]}

        expect(JSON.generate(scrub(:show, payload))).not_to match(/alice@example|zqxleak|leak\.test/)
      end

      it "scrubs host text that quotes any value it replaced, wherever the value sat" do
        positions = {
          cell: ->(v) { {"rows" => [{"id" => "1", "cells" => {"c" => {"type" => "text", "text" => v}}}]} },
          json_key: ->(v) { {"type" => "json", "value" => {v => 1}} },
          json_value: ->(v) { {"type" => "json", "value" => {"k" => v}} },
          html_text: ->(v) { {"type" => "html", "html" => "<p>#{v}</p>"} },
          html_attribute: ->(v) { {"type" => "frame", "src" => "/x", "html" => %(<abbr title="#{v}">x</abbr>)} },
          record_html_class: ->(v) { {"type" => "json", "value" => {"k" => %(<p class="#{v}">x</p>)}} },
          path_segment: ->(v) { {"type" => "link", "href" => "/admin/files/#{v}"} },
          file_name: ->(v) { {"type" => "image", "src" => "/files/#{v}.pdf"} },
          absolute_url: ->(v) { {"type" => "link", "href" => "https://leak.test/#{v}"} },
          query_value: ->(v) { {"type" => "link", "href" => "/admin/x?q=#{v}"} },
          option: ->(v) { {"control" => "select", "name" => "s", "param" => "x[s]", "value" => v, "options" => [{"label" => v, "value" => v}]} },
          text_field: ->(v) { {"control" => "text", "name" => "t", "param" => "x[t]", "value" => v} },
          mailto: ->(v) { {"type" => "link", "href" => "mailto:#{v}@private.test?subject=#{v}"} },
          tel: ->(v) { {"type" => "link", "href" => "tel:#{v}"} },
          lock: ->(v) { {"lock" => {"field" => "updated_at", "value" => "#{v}~tok"}} },
          fragment: ->(v) { {"type" => "link", "href" => "/admin/x##{v}"} },
          html_id: ->(v) { {"type" => "frame", "src" => "/x", "html" => %(<p id="#{v}">x</p>)} }
        }
        leaks = positions.filter_map do |where, build|
          sentinel = "zqx#{where.to_s.delete("_")}leak"
          out = described_class.new(seed: SEED, routes: %w[admin files x]).scrub_all([[:show, {"layout" => [build.call(sentinel), {"label" => "About #{sentinel}", "key" => "about"}]}]])
          where if JSON.generate(out).include?(sentinel)
        end

        expect(leaks).to be_empty
      end

      it "keeps only the route placeholders the API emits, never a braced file name" do
        payload = {"layout" => [{"type" => "image", "src" => "/files/%7BZQXLEAK%7D.pdf"}, {"type" => "link", "href" => "/admin/posts/%7Bparent_id%7D/comments/:id"}]}
        out = described_class.new(seed: SEED, routes: %w[admin posts comments files]).scrub_all([[:show, payload]]).first

        expect(JSON.generate(out)).not_to match(/zqxleak/i)
        expect(out["layout"].last["href"]).to eq("/admin/posts/%7Bparent_id%7D/comments/:id")
      end

      it "keeps a number field's value within its bounds, at its precision" do
        field = {"control" => "number", "name" => "rating", "param" => "x[rating]", "value" => 4.2, "input_html" => {"min" => 1, "max" => 5, "step" => "0.1"}}
        value = scrub(:form, field)["value"]

        expect(value).to be_between(1, 5)
        expect(value.to_s).to match(/\A\d\.\d\z/)
        expect(value).not_to eq(4.2)
        expect(scrub(:form, field.merge("value" => "3", "input_html" => {"min" => "1", "max" => "5"}))["value"]).to match(/\A[1-5]\z/)
      end

      it "fakes a datetime field's bounds in order and its value inside them, at the clock's precision" do
        field = {"control" => "datetime", "name" => "at", "param" => "x[at]", "value" => "2026-03-01T12:00:00Z", "input_html" => {"min" => "2026-03-01T09:00:00Z", "max" => "2026-03-01T17:00:00Z"}}
        out = scrub(:form, field)
        min, max, value = [*out["input_html"].values_at("min", "max"), out["value"]].map { Time.iso8601(it) }

        expect(min).to be <= max
        expect(value).to be_between(min, max)
        expect(out["value"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
        local = scrub(:form, field.merge("value" => "2026-03-01T12:00", "input_html" => {"min" => "2026-03-01T09:00"}))
        expect([local["value"], local["input_html"]["min"]]).to all(match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\z/))
        expect(local["value"]).to be >= local["input_html"]["min"]
        expect(out["value"]).not_to eq("2026-03-01T12:00:00Z")
      end

      it "scrubs host text that quotes a mailto address or tel number" do
        payload = {"layout" => [{"type" => "link", "label" => "Email", "href" => "mailto:alice@private.test"}, {"type" => "link", "label" => "Call", "href" => "tel:+15550123456"},
          {"label" => "Contact alice@private.test", "key" => "a"}, {"label" => "Ring +15550123456", "key" => "b"}]}

        expect(JSON.generate(scrub(:show, payload))).not_to match(/alice@private|5550123456/)
      end

      it "takes a mailto or tel link with malformed escapes" do
        %w[mailto:%zz mailto:a%2 tel:%].each { |href| expect(scrub(:show, {"type" => "link", "href" => href})["href"]).to start_with(href.split(":").first) }
      end

      it "keeps a faked field value within its maxlength and minlength" do
        short = scrub(:form, {"control" => "text", "name" => "c", "param" => "x[c]", "value" => "A", "input_html" => {"maxlength" => 1}})["value"]
        long = scrub(:form, {"control" => "text", "name" => "d", "param" => "x[d]", "value" => "Ann", "input_html" => {"minlength" => "12", "maxlength" => 20}})["value"]

        expect(short.size).to eq(1)
        expect(long.size).to be_between(12, 20)
      end

      it "quote-checks a scope's name, keeping its id" do
        payload = {"layout" => [{"type" => "text", "text" => "Jane Doe"}], "scopes" => [{"id" => "mine", "name" => "Mine for Jane Doe"}]}
        out = scrub(:show, payload)

        expect(out["scopes"].first["id"]).to eq("mine")
        expect(out["scopes"].first["name"]).not_to include("Jane")
      end

      it "keeps a minute-resolution datetime a datetime of the same precision" do
        value = scrub(:show, {"type" => "frame", "src" => "/x", "html" => %(<input type="datetime-local" value="2026-01-05T12:30">)})["html"][/value="([^"]+)"/, 1]

        expect(value).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\z/)
        expect(value).not_to eq("2026-01-05T12:30")
      end

      it "keeps a control's type even when a label of the same word was learned" do
        html = scrub(:show, {"type" => "frame", "src" => "/x", "html" => %(<label>Date</label><input type="date"><label>Email</label><input type="email">)})["html"]

        expect(html).to include(%(type="date"), %(type="email"))
      end

      it "keeps a number field's value on its step grid" do
        field = {"control" => "number", "name" => "n", "param" => "x[n]", "value" => 2.5, "input_html" => {"min" => 1, "max" => 5, "step" => "0.25"}}
        value = scrub(:form, field)["value"]

        expect(((value - 1) / 0.25) % 1).to eq(0)
        expect(value).to be_between(1, 5)
      end

      it "gives a hidden foreign key the mapping of the record it names, keeping its type" do
        form = {"form" => {"sections" => [{"fields" => [{"name" => "author_id", "param" => "account[author_id]", "label" => "Author", "control" => "hidden", "value" => 42},
          {"name" => "plan_id", "param" => "account[plan_id]", "label" => "Plan", "control" => "hidden", "value" => "7"}]}]}}
        authors, edit = scrub_with([{"rows" => [{"id" => "42"}, {"id" => "7"}]}, form])
        author, plan = edit.dig("form", "sections", 0, "fields").pluck("value")

        expect(author).to be_a(Integer)
        expect(author.to_s).to eq(authors["rows"].first["id"])
        expect(plan).to eq(authors["rows"].last["id"])
      end

      it "fits a faked email or url to its maxlength without breaking its shape" do
        email = scrub(:form, {"control" => "email", "name" => "e", "param" => "x[e]", "value" => "a@b.co", "input_html" => {"maxlength" => 10}})["value"]
        url = scrub(:form, {"control" => "url", "name" => "u", "param" => "x[u]", "value" => "https://a.co/x", "input_html" => {"maxlength" => 16}})["value"]

        expect(email).to match(/\A[^@\s]+@[^@\s]+\.[a-z]+\z/)
        expect(email.size).to be <= 10
        expect(url).to start_with("https://")
        expect(url.size).to be <= 16
      end

      it "keeps a number within a single declared bound" do
        below = scrub(:form, {"control" => "number", "name" => "a", "param" => "x[a]", "value" => 4, "input_html" => {"max" => 5}})["value"]
        above = scrub(:form, {"control" => "number", "name" => "b", "param" => "x[b]", "value" => 12, "input_html" => {"min" => 10}})["value"]

        expect(below).to be <= 5
        expect(above).to be >= 10
      end

      it "never fakes an id, a word or a number to itself, and never to another real id" do
        ids = (1000..3999).map(&:to_s)
        faked = scrub(:index, {"rows" => ids.map { {"id" => it} }})["rows"].pluck("id")

        expect(faked & ids).to be_empty
        expect(scrub(:index, {"rows" => [{"id" => "3858"}]})["rows"].first["id"]).not_to eq("3858")
        words = %w[lorem ipsum dolor sit amet]
        expect(words.map { scrub(:show, {"type" => "text", "text" => it})["text"] }.zip(words).count { |fake, real| fake == real }).to eq(0)
        expect((1..60).map { scrub(:show, {"type" => "number", "value" => it})["value"] }.zip(1..60).count { |fake, real| fake == real }).to eq(0)
      end

      it "keeps an attribute only when its value is in that attribute's vocabulary" do
        html = scrub(:show, {"type" => "frame", "src" => "/x", "html" => %(<input value="Jane"><a href="/x" target="Jane" rel="noopener Jane" role="Jane">a</a><a href="/y" target="_blank" rel="noopener noreferrer" role="button">b</a>)})["html"]

        expect(html).not_to include("Jane")
        expect(html).to include(%(target="_blank"), %(rel="noopener noreferrer"), %(role="button"))
      end

      it "keeps a whole number on a fractional step grid whole" do
        field = {"control" => "number", "name" => "n", "param" => "x[n]", "value" => 6, "input_html" => {"min" => 0, "max" => 10, "step" => "0.3"}}
        value = scrub(:form, field)["value"]

        expect(value).to be_an(Integer)
        expect([0, 3, 9]).to include(value)
      end

      it "treats angle-bracketed record text as text, and never keeps an unknown element's name" do
        text = scrub(:show, {"type" => "text", "text" => "Contact <alice@example.test>"})["text"]
        html = scrub(:show, {"type" => "html", "html" => "<p>hi</p><zqxleak-card>x</zqxleak-card>"})["html"]

        expect(text).not_to include("alice", "<")
        expect(html).not_to include("zqxleak")
        expect(html).to start_with("<p>")
      end

      it "requires a private seed, and moves dates by an offset only that seed gives" do
        expect { described_class.new(vocabulary: []) }.to raise_error(ArgumentError)
        expect { described_class.new(seed: "") }.to raise_error(ArgumentError, /private seed/)

        field = {"control" => "date", "name" => "born", "param" => "x[born]", "value" => "1980-05-06", "input_html" => {"min" => "1900-01-01", "max" => "2026-01-01"}}
        mins = %w[seed-a seed-b].map { described_class.new(seed: it).scrub_all([[:form, field]]).first["input_html"]["min"] }

        expect(mins.uniq.size).to eq(2)
        expect(mins).not_to include("1900-01-01")
      end

      it "keeps the fixtures' seed out of the code: from the environment, else a file in tmp/" do
        env = "REACTIVEADMIN_FIXTURES_SEED"
        saved = ENV.delete(env)
        Dir.mktmpdir do |root|
          allow(Rails).to receive(:root).and_return(Pathname(root))
          seed = ReactiveAdmin::Fixtures.seed

          expect(seed).to match(/\A\h{64}\z/)
          expect(ReactiveAdmin::Fixtures.seed).to eq(seed)
          file = Pathname(root).join(ReactiveAdmin::Fixtures::SEED_FILE)
          expect(file.read).to eq(seed)
          expect(file.stat.mode & 0o777).to eq(0o600)
          file.chmod(0o644)
          expect { ReactiveAdmin::Fixtures.seed }.to output(/restricted/).to_stderr
          expect(file.stat.mode & 0o777).to eq(0o600)
          ENV[env] = "from-env"
          expect(ReactiveAdmin::Fixtures.seed).to eq("from-env")
        end
      ensure
        ENV[env] = saved
      end

      it "learns a token query value before replacing it with the constant" do
        payload = {"layout" => [{"type" => "link", "href" => "/admin/posts?token=ZQXLEAK1"}, {"label" => "Use ZQXLEAK1?", "key" => "use"}]}

        expect(JSON.generate(scrub(:show, payload))).not_to include("ZQXLEAK1")
      end

      it "fits a six-character email to maxlength 6 exactly" do
        email = scrub(:form, {"control" => "email", "name" => "e", "param" => "x[e]", "value" => "a@b.co", "input_html" => {"maxlength" => 6}})["value"]

        expect(email.size).to be <= 6
        expect(email).to match(/\A[^@\s]+@[^@\s]+\.[a-z]+\z/)
      end

      it "fakes a number field's non-integer bounds in order and its value inside them" do
        field = {"control" => "number", "name" => "dose", "param" => "x[dose]", "value" => 2.75, "input_html" => {"min" => 2.5, "max" => 3.5}}
        out = scrub(:form, field)
        min, max = out["input_html"].values_at("min", "max")

        expect(min).to be <= max
        expect(out["value"]).to be_between(min, max)
        expect([min, max, out["value"]]).not_to include(2.5, 3.5, 2.75)
      end

      it "doesn't give a value back from a bound someone knows" do
        values = %w[1950-03-04 1971-07-08 1988-11-12 2003-01-02 2019-05-06]
        fields = values.each_with_index.map { |value, i| {"control" => "date", "name" => "b#{i}", "param" => "x[b#{i}]", "value" => value, "input_html" => {"min" => "1900-01-01"}} }
        outs = described_class.new(seed: SEED).scrub_all(fields.map { [:form, it] })
        recovered = outs.map { Date.iso8601("1900-01-01") + (Date.iso8601(it["value"]) - Date.iso8601(it["input_html"]["min"])) }

        expect(recovered.map(&:iso8601) & values).to be_empty
        outs.each { expect(Date.iso8601(it["value"])).to be >= Date.iso8601(it["input_html"]["min"]) }

        dose = scrub(:form, {"control" => "number", "name" => "dose", "param" => "x[dose]", "value" => 7.25, "input_html" => {"min" => 0.5}})
        expect(0.5 + dose["value"] - dose["input_html"]["min"]).not_to be_within(1e-9).of(7.25)
      end

      it "moves a date-only field by whole days even when its datetime shift is under a day" do
        # With SEED, this param's shift in seconds is 18932, which is zero whole days.
        field = {"control" => "date", "name" => "d", "param" => "x[d8210]", "value" => "2000-06-15", "input_html" => {"min" => "1990-01-01"}}

        expect(scrub(:form, field)["value"]).not_to eq("2000-06-15")
      end

      it "keeps only the query names the API reads, faking and learning the rest, key-only entries alike" do
        href = "/admin/posts?scope=all&q[title_cont]=x&page=2&alice%40private.test=1&zqxleakkey"
        out = scrub(:show, {"layout" => [{"type" => "link", "href" => href}, {"label" => "Ask zqxleakkey", "key" => "ask"}]})
        query = out["layout"][0]["href"].split("?", 2)[1]

        expect(query.split("&").map { it.split("=").first }.first(3)).to eq(%w[scope q[title_cont] page])
        expect(JSON.generate(out)).not_to include("alice", "private.test", "zqxleakkey")
      end

      it "moves kept bounds that admit only the original value along with it" do
        field = {"control" => "number", "name" => "n", "param" => "x[n]", "value" => 3, "input_html" => {"min" => 3, "max" => 3}}
        out = scrub(:form, field)

        expect(out["input_html"]["min"]).to eq(out["input_html"]["max"])
        expect(out["value"]).to eq(out["input_html"]["min"])
        expect(out["value"]).not_to eq(3)
      end

      it "never fits a fake back into the original" do
        fit = ->(value, max) { scrub(:form, {"control" => "email", "name" => "e", "param" => "x[e]", "value" => value, "input_html" => {"maxlength" => max}})["value"] }

        expect(fit.call("u@x.io", 6)).to match(/\A[a-z]@[a-z]\.io\z/).and(satisfy { it != "u@x.io" })
        expect(fit.call("u@x", 3)).not_to eq("u@x")
      end

      it "drops attribute names HTML doesn't define from record html, and learns them" do
        payload = {"layout" => [{"type" => "json", "value" => {"body" => %(<p class="note" data-patient-jane-doe="1" aria-label="x">hi</p>)}}, {"label" => "See patient-jane-doe", "key" => "see"}]}
        out = JSON.generate(scrub(:show, payload))

        expect(out).not_to include("jane")
        expect(out).to include("class=", "aria-label=")
      end

      it "learns what it drops from html, so a label quoting it is scrubbed" do
        payload = {"layout" => [{"type" => "json", "value" => {"body" => %(<p data-x="alice@private.test">hi</p><!-- bob@private.test -->)}},
          {"type" => "html", "html" => %(<p style="--who: carol@private.test">x</p>)},
          {"label" => "Mail alice@private.test, bob@private.test or carol@private.test", "key" => "mail"}]}

        expect(JSON.generate(scrub(:show, payload))).not_to match(/alice|bob|carol/)
      end

      it "keeps a frame input's value inside its bounds, by the rule a typed field follows" do
        html = scrub(:show, {"type" => "frame", "src" => "/x", "html" => %(<input type="number" name="n" min="1" max="5" value="3"><input type="date" name="d" min="1900-01-01" value="1980-05-06">)})["html"]
        number, date = Nokogiri::HTML5.fragment(html).css("input").to_a

        expect(number["min"]).to eq("1")
        expect(number["max"]).to eq("5")
        expect(number["value"]).to match(/\A[1-5]\z/).and(satisfy { it != "3" })
        expect(date["value"]).to be >= date["min"]
        expect([date["min"], date["value"]]).not_to include("1900-01-01", "1980-05-06")
      end

      it "fakes a lone kept bound that leaves the value no alternative, keeping the value inside it" do
        out = scrub(:form, {"control" => "number", "name" => "n", "param" => "x[n]", "value" => 1, "input_html" => {"max" => 1}})

        expect(out["value"]).to be <= out["input_html"]["max"]
        expect(out["value"]).not_to eq(1)
      end

      it "maps negative and Integer ids as ids, keeping their type and sign" do
        payload = {"rows" => [{"id" => -7, "display_name" => "x"}, {"id" => 12345, "display_name" => "y"}, {"id" => "-8", "display_name" => "z"}],
                   "fields" => [{"control" => "hidden", "name" => "author_id", "param" => "p[author_id]", "value" => -7}]}
        out = scrub(:show, payload)
        negative, positive, text = out["rows"].pluck("id")

        expect(negative).to be_an(Integer).and be_negative
        expect(positive).to be_an(Integer)
        expect(text).to match(/\A-\d+\z/)
        expect([negative, positive, text]).not_to include(-7, 12345, "-8")
        expect(out["fields"].first["value"]).to eq(negative)
      end

      it "keeps a status label only as a name of the enum its column or row shows" do
        scrubber = described_class.new(seed: SEED, vocabulary: {"people" => {"shift" => %w[june], "tone" => %w[white]}})
        payload = {"rows" => [{"id" => "1", "cells" => {"surname" => {"type" => "status", "label" => "White"}, "shift" => {"type" => "status", "label" => "June"}}}],
                   "layout" => [{"type" => "attributes_table", "rows" => [{"label" => "Surname", "value" => [{"type" => "status", "label" => "White"}]},
                     {"label" => "Shift", "value" => [{"type" => "status", "label" => "June"}]}]}, {"type" => "status", "label" => "White"}]}
        out = scrubber.scrub_all([[:show, payload, "people"]]).first

        expect(JSON.generate(out)).not_to include("White")
        expect(out["rows"].first.dig("cells", "shift", "label")).to eq("June")
        expect(out["layout"].first["rows"].last["value"].first["label"]).to eq("June")
      end

      it "keeps a status enum name that a record also holds out of the fixture" do
        scrubber = described_class.new(seed: SEED, vocabulary: {"people" => {"shift" => %w[june]}})
        payload = {"rows" => [{"id" => "1", "display_name" => "June", "cells" => {"shift" => {"type" => "status", "label" => "June"}}}]}

        expect(JSON.generate(scrubber.scrub_all([[:index, payload, "people"]]))).not_to include("June")
      end

      it "never returns the original, however the digests fall" do
        scrubber = described_class.new(seed: "private-seed-2329")
        expect(scrubber.send(:number, 1)).not_to eq(1)
        expect(scrubber.send(:fake, "1")).not_to eq("1")

        (1..200).each do |n|
          scrubber = described_class.new(seed: "property-#{n}")
          (1..9).each { |value| expect(scrubber.send(:number, value)).not_to eq(value) }
          %w[1 7 a Z x 2020-01-31].each { |value| expect(scrubber.send(:fake, value)).not_to eq(value) }
        end
      end

      it "keeps a frame link's validated method" do
        html = scrub(:show, {"type" => "frame", "src" => "/x", "html" => %(<a href="/admin/posts/5" data-method="delete">Remove</a><a href="/x" data-method="Jane">x</a>)})["html"]

        expect(html).to include(%(data-method="delete"))
        expect(html).not_to include("Jane")
      end

      it "gives every option of a long frame select its own value" do
        codes = ("aa".."zz").first(400)
        html = scrub(:show, {"type" => "frame", "src" => "/x", "html" => "<select name=\"c\">#{codes.map { %(<option value="#{it}">#{it}</option>) }.join}</select>"})["html"]
        values = Nokogiri::HTML5.fragment(html).css("option").map { it["value"] }

        expect(values.uniq.size).to eq(codes.size)
      end

      it "takes an empty url in html" do
        expect(scrub(:show, {"type" => "frame", "src" => "/x", "html" => %(<a href="">Here</a>)})["html"]).to include(%(href=""))
      end

      it "scrubs a class or style built from a record, and keeps the host's own" do
        payload = {"layout" => [{"type" => "text", "text" => "Jane Doe"}, {"type" => "html", "html" => %(<p class="patient-jane-doe note" style="--label: 'x'">a</p><p class="note" style="color: red">b</p>)}]}
        html = scrub(:show, payload)["layout"].last["html"]

        expect(html).not_to match(/jane|--label/i)
        expect(html).to include(%(<p class="note" style="color: red">))
      end

      it "takes a negative integer hidden id" do
        form = {"form" => {"sections" => [{"fields" => [{"name" => "id", "param" => "x[id]", "label" => "Id", "control" => "hidden", "value" => -3}]}]}}

        expect { scrub(:form, form) }.not_to raise_error
      end

      it "keeps the date in a frame input a date" do
        html = scrub(:show, {"type" => "frame", "html" => %(<input type="date" value="2026-01-05"><input type="number" value="12.5"><input value="Jane Doe">), "src" => "/x"})["html"]

        expect(html).to match(/value="\d{4}-\d{2}-\d{2}"/).and match(/value="\d+\.\d"/).and(satisfy { !it.include?("2026-01-05") && !it.include?("Jane") })
      end

      it "keeps enum names only where the payload marks a choice" do
        scrubber = described_class.new(seed: SEED, vocabulary: {"people" => {"shift" => %w[june grace white]}})
        payload = {"rows" => [{"id" => "4", "display_name" => "June White", "cells" => {"name" => {"type" => "text", "text" => "Grace"}, "shift" => {"type" => "status", "label" => "June"}}}],
                   "fields" => [field("first_name", "Grace", "control" => "text"), field("shift", "june", "options" => [{"label" => "June", "value" => "june"}, {"label" => "Grace", "value" => "4"}])]}

        scrubbed = scrubber.scrub_all([[:index, payload, "people"]]).first
        row = scrubbed["rows"].first
        text, shift = scrubbed["fields"]

        expect([row["display_name"], row.dig("cells", "name", "text"), text["value"], shift["options"].last["label"]]).to all(satisfy { !it.match?(/june|grace|white/i) })
        expect(row.dig("cells", "shift", "label")).to eq("June")
        expect(shift["value"]).to eq("june")
        expect(shift["options"].first).to eq("label" => "June", "value" => "june")
      end

      it "keeps an enum name only as a choice of its own attribute, and never a record's label" do
        scrubber = described_class.new(seed: SEED, vocabulary: {"people" => {"shift" => %w[june grace]}, "colors" => {"tone" => %w[white]}})
        rows = {"rows" => [{"id" => "grace", "display_name" => "Grace"}]}
        form = {"fields" => [field("surname", "White", "options" => [{"label" => "White", "value" => "White"}]),
          field("shift", "grace", "options" => [{"label" => "Grace", "value" => "grace"}]),
          field("shift", "june", "options" => [{"label" => "June", "value" => "june"}])]}
        surname, mentor, shift = scrubber.scrub_all([[:index, rows, "people"], [:form, form, "people"]]).last["fields"]

        expect([surname["options"].first, surname["value"]].to_s).not_to match(/white/i)
        expect(mentor["options"].first.values).not_to include("grace", "Grace")
        expect(shift["options"].first).to eq("label" => "June", "value" => "june")
      end

      it "scrubs row action text and row classes that differ between rows, and reports the host text it kept" do
        rows = %w[Bob Ann].map.with_index do |name, index|
          {"id" => index.to_s, "class_name" => "diagnosis-#{name.downcase}", "actions" => [
            {"key" => "call", "kind" => "member", "label" => "Call #{name} Smith (guardian)", "confirm" => "Call #{name}?", "disabled_reason" => "#{name} opted out"},
            {"key" => "archive", "kind" => "member", "label" => "Archive", "confirm" => "Sure?"}
          ]}
        end

        scrubbed = scrubber.scrub_all([[:index, {"rows" => rows}]]).first["rows"]

        expect(JSON.generate(scrubbed)).not_to match(/bob|ann|smith|guardian|diagnosis|opted/i)
        expect(scrubbed.first["actions"].last).to include("label" => "Archive", "confirm" => "Sure?")
        expect(scrubber.kept).to eq(%w[Archive Sure?])
      end

      it "keeps only the structural values of a query" do
        meta = {"scopes" => [{"id" => "active", "name" => "Active"}], "columns" => [{"key" => "title", "label" => "Title", "sortable" => true, "sort_key" => "title"}]}
        paths = ["/previews?context=ZQXLEAK-secret&page=jane", "/admin/posts?scope=jane_doe&order=jane_asc&format=jane", "/admin/posts?scope=active&order=title_desc&page=2&per_page=30"]

        scrubbed = described_class.new(seed: SEED, routes: %w[admin posts previews]).scrub_all([[:meta, meta], [:show, {"layout" => paths.map { {"type" => "link", "href" => it} }}]]).last["layout"].pluck("href")

        expect(scrubbed.first(2).join).not_to match(/zqxleak|jane/i)
        expect(scrubbed.last).to eq(paths.last)
      end

      it "records a Rails form frame the same whatever its CSRF token, keeping its control names" do
        frame = ->(token) { {"type" => "frame", "src" => "/x", "html" => %(<form action="/x" method="post"><input type="hidden" name="authenticity_token" value="#{token}"><input type="text" name="post[title]" value="Jane"></form>)} }

        html = [frame.call("aB3+/x=="), frame.call("Zz9-other")].map { described_class.new(seed: SEED).scrub_all([[:show, it]]).first["html"] }

        expect(html.uniq.size).to eq(1)
        expect(html.first).to include(%(name="authenticity_token"), %(name="post[title]"))
        expect(html.first).not_to include("Jane")
      end

      it "scrubs a fragment-only link to the same fake as its target, and keeps a bare #" do
        html = scrub(:show, {"type" => "frame", "src" => "/x", "html" => %(<a href="#details">More</a><a href="#">Top</a><section id="details">x</section>)})["html"]
        fragment = Nokogiri::HTML5.fragment(html)

        expect(fragment.css("a").map { it["href"] }).to eq(["##{fragment.at_css("section")["id"]}", "#"])
        expect(html).not_to include("details")
      end
    end

    it "never gives two ids the same fake" do
      ids = (1..300).map(&:to_s)
      fakes = scrubber.scrub_all([[:index, {"rows" => ids.map { {"id" => it, "display_name" => "n"} }}]]).first["rows"].pluck("id")

      expect(fakes.uniq.size).to eq(300)
    end
  end
end
