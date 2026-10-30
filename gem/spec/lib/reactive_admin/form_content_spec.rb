require "rails_helper"

RSpec.describe ReactiveAdmin::FormContent do
  subject(:content) { described_class.new(controller, nil) }

  let(:controller) { double(request: double(host: "example.test", base_url: "http://example.test")) }
  let(:marker) { described_class.method(:marker) }

  before do
    allow(ReactiveAdmin::AA).to receive(:config_of).and_return(ReactiveAdmin::Registry.find("posts"))
    allow(ReactiveAdmin::Authorizer).to receive(:for).and_return(ReactiveAdmin::Authorizer.new(nil))
  end

  def split(html) = content.split(html)

  describe "#split" do
    it "gives each marker the content before it, and the remainder under no id" do
      expect(split("<p>a</p>#{marker.call(1)}<p>b</p>#{marker.call(2)}<p>c</p>")).to eq([["1", "<p>a</p>"], ["2", "<p>b</p>"], [nil, "<p>c</p>"]])
    end

    it "copies the elements open around a marker into each part they span" do
      html = %(<div class="panel"><h3>Plan</h3><div class="panel_contents">#{marker.call(1)}</div></div><p>after</p>)

      parts = split(html)

      expect(parts.first).to eq(["1", %(<div class="panel"><h3>Plan</h3><div class="panel_contents"></div></div>)])
      expect(parts.last).to eq([nil, %(<div class="panel"><div class="panel_contents"></div></div><p>after</p>)])
    end

    it "keeps the order of content that sits both before and after an input in one wrapper" do
      parts = split("<div><p>a</p>#{marker.call(1)}<p>b</p>#{marker.call(2)}<p>c</p></div>")

      expect(parts).to eq([["1", "<div><p>a</p></div>"], ["2", "<div><p>b</p></div>"], [nil, "<div><p>c</p></div>"]])
    end

    it "has only the remainder when there are no markers" do
      expect(split("<p>a</p>")).to eq([[nil, "<p>a</p>"]])
    end
  end

  describe "#nodes" do
    it "walks the html into typed nodes" do
      expect(content.nodes("<h3>Hi</h3><p>there</p>").pluck(:type)).to eq(%w[heading text])
    end

    it "is empty for nothing, and for wrappers with nothing in them" do
      expect(content.nodes("")).to eq([])
      expect(content.nodes(%(<div><div class="panel"><div class="panel_contents"></div></div></div>))).to eq([])
    end

    it "turns a panel left with only its title into a heading" do
      nodes = content.nodes(%(<div class="panel"><h3>New Plan</h3><div class="panel_contents"></div></div>))

      expect(nodes).to eq([{type: "heading", level: 3, children: [{type: "text", text: "New Plan"}]}])
    end

    it "keeps a panel that holds something" do
      nodes = content.nodes(%(<div class="panel"><h3>Plan</h3><div class="panel_contents"><p>x</p></div></div>))

      expect(nodes).to match([a_hash_including(type: "panel", title: "Plan", children: [a_hash_including(type: "text")])])
    end

    it "never lets markup that claims to be an action or a frame become one" do
      html = '<a href="/x" data-method="delete" data-confirm="Sure">Go</a><form method="post" action="/y"><button>Pay</button></form>'

      expect(content.nodes(html).to_json).not_to match(/"type":"(action|frame|iframe)"/)
    end
  end
end
