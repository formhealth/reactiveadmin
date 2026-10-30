require "tmpdir"

# A stand-in for `rake reactiveadmin:client:build`: the manifest the shell reads, and the files it names.
module UiHelpers
  MANIFEST = {
    "index.html" => {"file" => "assets/index-abc123.js", "isEntry" => true, "css" => ["assets/index-abc123.css"], "imports" => ["_vendor-9f.js"]},
    "_vendor-9f.js" => {"file" => "assets/vendor-9f.js", "css" => ["assets/vendor-9f.css"]},
    "src/classic/uiToggle.ts" => {"file" => "assets/uiToggle-77.js", "isEntry" => true}
  }.freeze

  def write_client_build(dir)
    FileUtils.mkdir_p(File.join(dir, "assets"))
    File.write(File.join(dir, "manifest.json"), MANIFEST.to_json)
    %w[assets/index-abc123.js assets/vendor-9f.js assets/index-abc123.css assets/vendor-9f.css assets/uiToggle-77.js].each { File.write(File.join(dir, it), "/* #{it} */") }
  end

  # Installs a throwaway client build for the block; `settings` override the UI configuration.
  def with_ui(available: ->(_user) { true }, **settings)
    ui = ReactiveAdmin.config.ui
    names = %i[enabled available default client_assets asset_prefix]
    original = names.index_with { ui.public_send(it) }
    Dir.mktmpdir do |dir|
      write_client_build(dir)
      ui.available = available
      ui.client_assets = dir
      settings.each { |name, value| ui.public_send("#{name}=", value) }
      yield dir
    end
  ensure
    original.each { |name, value| ui.public_send("#{name}=", value) }
  end

  # What a browser sends for a page load of someone who chose the new admin.
  def navigation(cookie: "reactiveadmin_ui=new", **headers)
    {"Cookie" => cookie, "Sec-Fetch-Dest" => "document"}.compact.merge(headers.transform_keys { it.to_s.tr("_", "-") })
  end

  def shell? = response.media_type == "text/html" && response.body.include?('<div id="root">')
end

RSpec.configure { it.include UiHelpers }
