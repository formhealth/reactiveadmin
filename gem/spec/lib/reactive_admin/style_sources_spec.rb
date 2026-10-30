RSpec.describe ReactiveAdmin::StyleSources do
  let(:root) { Pathname(Dir.mktmpdir) }
  let(:helpers) { Struct.new(:active_admin_config).new(Struct.new(:resource_name).new("Post")) }

  before { allow(Rails).to receive(:root).and_return(root) }

  after { FileUtils.remove_entry(root) }

  def write(path, text)
    root.join(path).tap { it.dirname.mkpath }.write(text)
  end

  describe ".locate" do
    it "finds nothing outside a trace" do
      write("app/admin/posts.rb", %(div style: "margin-top: 8px;"\n))

      expect(described_class.locate("margin-top: 8px;")).to be_nil
    end

    it "scans templates and helpers for the exact string, relative to the app" do
      write("app/admin/posts.rb", %(ActiveAdmin.register Post do\n  div style: "margin-top: 8px;" do\n  end\nend\n))
      write("app/views/admin/posts/_x.html.erb", %(<p class="p-4 lg:p-4">a</p>\n<p style="margin-top: 8px;">b</p>\n))

      described_class.trace do
        expect(described_class.locate("margin-top: 8px;")).to eq("app/admin/posts.rb:2, app/views/admin/posts/_x.html.erb:2")
        expect(described_class.locate("p-4")).to eq("app/views/admin/posts/_x.html.erb:1")
        expect(described_class.locate("nothing here")).to be_nil
      end
    end

    it "limits the lines it names" do
      write("app/admin/many.rb", Array.new(5) { %(div style: "margin-top: 8px"\n) }.join)

      described_class.trace { expect(described_class.locate("margin-top: 8px").split(", ").size).to eq(3) }
    end

    it "keeps tracing until the outermost trace ends" do
      described_class.trace do
        described_class.trace { nil }

        expect(described_class).to be_tracing
      end
    end

    it "stops tracing afterwards" do
      described_class.trace { expect(described_class).to be_tracing }

      expect(described_class).not_to be_tracing
    end
  end

  describe "tracing Arbre tags" do
    before { allow(Rails).to receive(:root).and_return(Pathname(File.expand_path("../../..", __dir__))) }

    def build(&) = Arbre::Context.new({}, helpers, &).to_s

    it "notes the DSL line that built a styled or classed tag, per resource" do
      described_class.trace do
        build { div style: "margin-top:  8px", class: "flex mt-4" }

        line = __LINE__ - 2
        expect(described_class.locate("margin-top: 8px", resource: "Post")).to eq("spec/lib/reactive_admin/style_sources_spec.rb:#{line}")
        expect(described_class.locate("mt-4", resource: "Post")).to eq("spec/lib/reactive_admin/style_sources_spec.rb:#{line}")
      end
    end

    it "keeps another resource's lines apart" do
      described_class.trace do
        build { div style: "margin-top: 8px" }

        expect(described_class.locate("margin-top: 8px", resource: "Author")).to be_nil
      end
    end

    it "leaves tags alone when not tracing" do
      expect(build { div style: "margin-top: 8px" }).to include('style="margin-top: 8px"')
    end
  end

  describe "in the walker's diagnostics" do
    before { ReactiveAdmin.diagnostics.clear }

    it "names the source of an unknown class and of an inline style" do
      write("app/admin/posts.rb", %(div class: "p-4"\ndiv style: "position: sticky; top: 20px"\n))

      described_class.trace do
        ReactiveAdmin::HtmlNodes.nodes('<div class="p-4"><ul><li>x</li></ul></div><div style="position: sticky; top: 20px"><ul><li>y</li></ul></div>', resource: "Post")
      end

      expect(ReactiveAdmin.diagnostics.entries).to contain_exactly(
        a_hash_including(kind: :unknown_layout_class, class: "p-4", source: "app/admin/posts.rb:1"),
        a_hash_including(kind: :inline_style_ignored, style: "position: sticky; top: 20px", ignored: "position: sticky; top: 20px", source: "app/admin/posts.rb:2")
      )
    end

    it "records no source when not tracing" do
      ReactiveAdmin::HtmlNodes.nodes('<div class="p-4"><ul><li>x</li></ul></div>')

      expect(ReactiveAdmin.diagnostics.entries.first).not_to have_key(:source)
    end
  end
end
