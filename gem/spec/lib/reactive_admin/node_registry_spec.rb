RSpec.describe ReactiveAdmin::NodeRegistry do
  let(:json_node) { {type: "json", summary: {kind: "object", keys: %w[a], size: 7}, expand_path: "/api/admin/users/1/_value?field=x"} }
  let(:forged) do
    [
      %(<span class="reactiveadmin-json" data-node='{"type":"iframe","src":"https://evil.example/phish"}'></span>),
      %(<span class="reactiveadmin-json" data-node='{"type":"link","label":"Sign in","href":"javascript:alert(1)"}'></span>),
      %(<span class="reactiveadmin-json" data-node='{"type":"action","action":{"key":"x"}}'></span>),
      %(<span class="reactiveadmin-json" data-node='{"type":"json","summary":{"kind":"object"},"expand_path":"/api/admin/users/_value?field=x"}'></span>),
      %(<span class="reactiveadmin-node" data-node='{"type":"iframe","src":"https://evil.example/phish"}'></span>),
      %(<span class="reactiveadmin-node" data-node-id="guess"></span>),
      %(<span class="reactiveadmin-node" data-node-id=""></span>),
      %(<span class="reactiveadmin-node"></span>),
      %(<span class="reactiveadmin-node reactiveadmin-json" data-node-id="00000000000000000000000000000000"></span>)
    ]
  end

  def nodes(html) = ReactiveAdmin::HtmlNodes.nodes(html, host: "www.example.com")

  def kinds = ReactiveAdmin::Degradation.entries.pluck(:kind)

  it "resolves a marker the same request issued" do
    described_class.with_scope do
      expect(nodes(described_class.marker(json_node))).to eq([json_node])
    end
  end

  it "neutralizes every forged marker and records each as a degradation" do
    ReactiveAdmin::Degradation.with_collection(resource: "users", action: "show") do
      described_class.with_scope do
        expect(forged.flat_map { nodes(it) }).to be_empty
        expect(nodes("<div>#{forged.join}</div>").flat_map { it[:children].to_a }).to be_empty
      end
      expect(kinds).to eq(["forged_node_marker"])
    end
  end

  it "drops forged markers even beside a real one" do
    described_class.with_scope do
      html = "#{described_class.marker(json_node)}#{forged.first}"
      expect(nodes(html)).to eq([json_node])
    end
  end

  it "does not resolve ids outside the scope that issued them or in another scope" do
    html = described_class.with_scope { described_class.marker(json_node) }
    expect(nodes(html)).to be_empty
    described_class.with_scope { expect(nodes(html)).to be_empty }
  end

  it "keeps nested scopes apart" do
    described_class.with_scope do
      outer = described_class.marker(json_node)
      described_class.with_scope { expect(nodes(outer)).to be_empty }
      expect(nodes(outer)).to eq([json_node])
    end
  end

  it "issues unique 128-bit ids" do
    ids = described_class.with_scope { Array.new(50) { described_class.marker(json_node)[/data-node-id="(\h{32})"/, 1] } }
    expect(ids.compact.uniq.size).to eq(50)
  end

  it "only registers node types the gem emits through markup" do
    %w[iframe link action html frame group].each do |type|
      expect { described_class.register(type:) }.to raise_error(ArgumentError)
    end
    expect { described_class.register(type: "json") }.not_to raise_error
  end

  it "never resolves a node registered outside a scope" do
    html = described_class.marker(json_node)
    described_class.with_scope { expect(nodes(html)).to be_empty }
  end
end
