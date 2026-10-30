RSpec.describe ReactiveAdmin::MediaNodes do
  def media(html, host: "app.test") = described_class.for(Nokogiri::HTML5.fragment(html).children.first, host:)

  around do |example|
    ReactiveAdmin.config.html_trusted_hosts = ["cdn.test"]
    example.run
  ensure
    ReactiveAdmin.config.html_trusted_hosts = []
  end

  it "builds image nodes with the declared size only when it is sane" do
    expect(media('<img src="https://cdn.test/a/" alt=" scan " width="320" height="0">')).to eq(type: "image", src: "https://cdn.test/a/", alt: "scan", width_px: 320)
    expect(media('<img src="/a.png" width="100%" height="99999">')).to eq(type: "image", src: "/a.png", alt: "")
  end

  it "refuses sources that are not http(s) on this site or a trusted host" do
    sources = ["data:image/png;base64,iVBORw0KGgo=", "javascript:x()", "//cdn.test/a.png", "https://evil.test/a.png",
      "http://app.test.evil.test/a.png", "a.png", "https:cdn.test/a.png", "ftp://cdn.test/a.png", ""]

    expect(sources.filter_map { media(%(<img src="#{it}">)) }).to eq([])
  end

  it "builds document nodes from embed, object and iframe, titled when the markup says so" do
    expect(media('<embed src="https://cdn.test/a/" type="application/pdf">')).to eq(type: "document", src: "https://cdn.test/a/", mime: "application/pdf")
    expect(media('<object data="/a.pdf" type="application/pdf" title=" Lab "></object>')).to include(title: "Lab")
    expect(media('<iframe src="/a.pdf#page=2"></iframe>')).to include(type: "document")
  end

  it "refuses documents that are not declared or provable pdfs" do
    html = ['<embed src="/a" type="application/pdf">', '<embed src="https://cdn.test/a/" type="text/html">', '<embed src="/a.pdf">',
      '<iframe src="/admin/authors"></iframe>', '<iframe src="https://cdn.test/page/"></iframe>', '<embed src="data:application/pdf;base64,AA==" type="application/pdf">']

    expect(html.filter_map { media(it) }).to eq([])
  end
end
