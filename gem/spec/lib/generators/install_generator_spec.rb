require "generators/reactiveadmin/install/install_generator"

RSpec.describe ReactiveAdmin::Generators::InstallGenerator do
  let(:root) { Pathname(Dir.mktmpdir) }
  let(:initializer) { root.join("config/initializers/reactive_admin.rb") }
  let(:routes) { root.join("config/routes.rb") }

  before do
    FileUtils.mkdir_p(root.join("config/initializers"))
    FileUtils.cp(Rails.root.join("config/routes.rb"), routes)
    routes.write(routes.read.sub(/^\s*ReactiveAdmin\.routes\(self\)\n/, ""))
  end

  after { FileUtils.rm_rf(root) }

  def generate(*args)
    out = StringIO.new
    $stdout = out
    described_class.start(args, destination_root: root.to_s)
    out.string
  ensure
    $stdout = STDOUT
  end

  def capture_error
    err = StringIO.new
    $stderr = err
    yield
    err.string
  ensure
    $stderr = STDERR
  end

  def load_initializer
    config = ReactiveAdmin::Configuration.new
    allow(ReactiveAdmin).to receive(:configure).and_yield(config)
    load initializer.to_s
    config
  end

  # Answers questions by pattern, as someone at a terminal would.
  def answering(answers)
    allow_any_instance_of(described_class).to receive(:interactive?).and_return(true)
    allow_any_instance_of(described_class).to receive(:ask) do |_, question, **|
      answers.find { |pattern, _| question.match?(pattern) }&.last or raise "unexpected question: #{question}"
    end
  end

  def admin_files(**files)
    FileUtils.mkdir_p(root.join("app/admin"))
    files.each { |name, body| root.join("app/admin/#{name}.rb").write(body) }
  end

  def bundle(*gems)
    root.join("Gemfile.lock").write("GEM\n  specs:\n#{gems.map { "    #{it} (1.0.0)\n" }.join}")
  end

  it "is found as reactiveadmin:install" do
    expect(Rails::Generators.find_by_namespace("reactiveadmin:install")).to eq(described_class)
  end

  it "writes an initializer with the secure defaults that loads against the configuration" do
    generate
    config = ReactiveAdmin::Configuration.new
    allow(ReactiveAdmin).to receive(:configure).and_yield(config)
    load initializer.to_s

    expect(config).to have_attributes(namespace: :admin, mount_path: "/api", expose: :listed, implicit_defaults: :secure, require_lock: true)
  end

  it "mounts the routes right after ActiveAdmin's" do
    generate
    expect(routes.read).to include("  ActiveAdmin.routes(self)\n  ReactiveAdmin.routes(self)\n")
  end

  it "mounts when the only ReactiveAdmin call is commented out" do
    routes.write(routes.read.sub("  ActiveAdmin.routes(self)\n", "  ActiveAdmin.routes(self)\n  # ReactiveAdmin.routes(self)\n"))
    generate
    expect(routes.read).to include("  ActiveAdmin.routes(self)\n  ReactiveAdmin.routes(self)\n")
  end

  it "recognizes routes written without parentheses" do
    routes.write(routes.read.sub("ActiveAdmin.routes(self)", "ActiveAdmin.routes(self)\n  ReactiveAdmin.routes self"))
    expect { generate }.not_to change { routes.read }
  end

  it "leaves a conditional ActiveAdmin.routes call to a manual mount" do
    routes.write(routes.read.sub("ActiveAdmin.routes(self)", "ActiveAdmin.routes(self) if Rails.env.development?"))
    expect(generate).to include("ActiveAdmin.routes(self) not found")
    expect(routes.read).not_to include("ReactiveAdmin")
  end

  it "mounts after a call with a trailing comment" do
    routes.write(routes.read.sub("ActiveAdmin.routes(self)", "ActiveAdmin.routes(self) # classic admin"))
    generate
    expect(routes.read).to include("ReactiveAdmin.routes(self)\n")
  end

  it "mounts in a CRLF routes file, keeping its line endings" do
    routes.write(routes.read.gsub("\n", "\r\n"))
    generate

    expect(routes.read).to include("  ActiveAdmin.routes(self)\r\n  ReactiveAdmin.routes(self)\r\n")
    expect(routes.read).not_to match(/[^\r]\n/)
  end

  it "serves the namespace ActiveAdmin's initializer sets, and says where to find it" do
    root.join("config/initializers/active_admin.rb").write("  config.default_namespace = :ops\n")
    output = generate

    expect(initializer.read).to include("config.namespace = :ops", "/api/ops.")
    expect(output).to include("/api/ops/_manifest")
  end

  it "takes the namespace as an option" do
    generate("--namespace", "backoffice")
    expect(initializer.read).to include("config.namespace = :backoffice")
  end

  it "writes nothing for the root namespace unless a name is given" do
    root.join("config/initializers/active_admin.rb").write("  config.default_namespace = false\n")
    before = routes.read
    output = capture_error { generate }

    expect(initializer).not_to exist
    expect(routes.read).to eq(before)
    expect(output).to include("--namespace")

    generate("--namespace", "ops")
    expect(initializer.read).to include("config.namespace = :ops")
  end

  it "reads a quoted namespace symbol or string" do
    [':"ops"', ":'ops'", '"ops"'].each do |value|
      root.join("config/initializers/active_admin.rb").write("  config.default_namespace = #{value} # set by ops\n")
      FileUtils.rm_f(initializer)
      generate
      expect(initializer.read).to include("config.namespace = :ops"), value
    end
  end

  it "writes nothing when ActiveAdmin's initializer assigns the namespace more than once" do
    root.join("config/initializers/active_admin.rb").write("  config.default_namespace = :admin\n  config.default_namespace = :ops if Rails.env.production?\n")
    output = capture_error { generate }

    expect(initializer).not_to exist
    expect(output).to include(":admin and :ops", "--namespace")
  end

  it "refuses a --namespace that isn't a plain name" do
    output = capture_error { generate("--namespace", "back-office") }

    expect(initializer).not_to exist
    expect(output).to include("plain name")
  end

  it "writes nothing for a namespace it can't read" do
    root.join("config/initializers/active_admin.rb").write("  config.default_namespace = ENV.fetch(\"AA_NS\").to_sym\n")
    output = capture_error { generate }

    expect(initializer).not_to exist
    expect(output).to include("ENV.fetch", "--namespace")
  end

  it "doesn't vouch for the exposure of an initializer it kept" do
    initializer.write("ReactiveAdmin.configure { |config| config.namespace = :admin }\n")
    output = generate

    expect(output).to include("was kept as it is", "config.expose = :listed")
    expect(output).not_to include("the initializer sets")
  end

  it "prints the next steps" do
    allow_any_instance_of(described_class).to receive(:packaged_client?).and_return(false)
    expect(generate).to include("Prune app/admin/menu.rb", "TODO(setup)", "bin/rails reactiveadmin:client:build", "bin/rails reactiveadmin:doctor")
  end

  it "changes nothing when run twice" do
    generate
    before = [initializer.read, routes.read]
    output = generate

    expect([initializer.read, routes.read]).to eq(before)
    expect(routes.read.scan("ReactiveAdmin.routes(self)").size).to eq(1)
    expect(output).to match(/skip.*reactive_admin\.rb/).and match(/identical.*ReactiveAdmin\.routes/)
  end

  it "keeps an existing initializer under the other name" do
    root.join("config/initializers/reactiveadmin.rb").write("# mine\n")
    generate
    expect(initializer).not_to exist
  end

  it "refuses to mount without ActiveAdmin's routes" do
    routes.write("Rails.application.routes.draw do\nend\n")
    expect(generate).to include("ActiveAdmin.routes(self) not found")
    expect(routes.read).not_to include("ReactiveAdmin")
  end

  it "points Pundit hosts at the adapter and the after_authorize hook" do
    bundle("pundit")
    output = generate

    expect(initializer.read).to include("ActiveAdmin::PunditAdapter", "# config.after_authorize = ->(controller) { controller.skip_authorization }")
    expect(output).to include("config.authorization_adapter = ActiveAdmin::PunditAdapter")
  end

  it "doesn't warn when ActiveAdmin already uses the adapter" do
    bundle("cancancan")
    root.join("config/initializers/active_admin.rb").write("  config.authorization_adapter = ActiveAdmin::CanCanAdapter\n")
    output = generate

    expect(initializer.read).to include("ActiveAdmin::CanCanAdapter")
    expect(output).not_to include("warning")
  end

  it "takes the adapter named as a string, as ActiveAdmin does" do
    bundle("pundit")
    root.join("config/initializers/active_admin.rb").write("  config.authorization_adapter = \"ActiveAdmin::PunditAdapter\"\n")

    expect(generate).not_to include("warning")
  end

  it "reads the namespace from a CRLF ActiveAdmin initializer, and still refuses the root one" do
    root.join("config/initializers/active_admin.rb").write("  config.default_namespace = :ops\r\n")
    generate
    expect(initializer.read).to include("config.namespace = :ops")

    FileUtils.rm_f(initializer)
    root.join("config/initializers/active_admin.rb").write("  config.default_namespace = false # root\r\n")
    capture_error { generate }
    expect(initializer).not_to exist
  end

  it "asks for a client build only when the gem has no prebuilt one" do
    allow_any_instance_of(described_class).to receive(:packaged_client?).and_return(false)
    expect(generate).to include("bin/rails reactiveadmin:client:build")

    FileUtils.rm_f(initializer)
    allow_any_instance_of(described_class).to receive(:packaged_client?).and_return(true)
    output = generate
    expect(output).to include("ships a prebuilt client")
    expect(output).not_to include("reactiveadmin:client:build")
  end

  describe "presets" do
    before do
      admin_files(
        posts: "ActiveAdmin.register Post do\nend\n",
        plans: "ActiveAdmin.register Plan, as: \"ConstructPlan\" do\nend\n",
        users: "ActiveAdmin.register Admin::User do\nend\n",
        comments: "ActiveAdmin.register Comment do\n  belongs_to :post\nend\n",
        dashboard: "ActiveAdmin.register_page \"Dashboard\" do\n  content title: \"Dashboard\" do\n  end\nend\n",
        reports: "ActiveAdmin.register_page \"Back Office\" do\nend\n"
      )
    end

    let(:menu) { root.join("app/admin/menu.rb") }

    it "defaults to guided: :listed, an annotated initializer, and a menu of every registration to prune" do
      generate

      expect(load_initializer).to have_attributes(expose: :listed, strict_defaults: false)
      expect(initializer.read).to include("TODO(setup)", "Nested under a required parent, so the menu can't place them: comments")
      expect(menu.read.scan(/^  resources :(\w+)$/).flatten).to eq(%w[construct_plans posts admin_users])
      expect(menu.read.scan(/^  page :(\w+)$/).flatten).to eq(%w[dashboard back_office])
    end

    it "lists the same keys the registry uses, for the dummy app's own registrations" do
      FileUtils.rm_rf(root.join("app/admin"))
      FileUtils.cp_r(Rails.root.join("app/admin"), root.join("app/admin"))
      FileUtils.rm_f(menu)
      # An alias on the call's next line still names the registration.
      plans = root.join("app/admin/index_construct_plans.rb")
      plans.write(plans.read.sub('ActiveAdmin.register Plan, as: "ConstructPlan" do', "ActiveAdmin.register Plan,\n  as: \"ConstructPlan\" do"))
      generate

      registry = ReactiveAdmin::Registry
      placeable = registry.resources.reject { ReactiveAdmin::Paths.nested?(it) }.map { registry.route_key(it) } - %w[admin_comments]
      expect(menu.read.scan(/^  resources :(\w+)$/).flatten).to match_array(placeable)
      expect(menu.read.scan(/^  page :(\w+)$/).flatten).to match_array(registry.pages.map { ReactiveAdmin::Menu.page_key(it) })
    end

    it "checks nesting per registration, not per file" do
      FileUtils.rm_rf(root.join("app/admin"))
      admin_files(blog: "ActiveAdmin.register Post do\nend\n\nActiveAdmin.register Comment do\n  belongs_to :post\nend\n")
      generate

      expect(menu.read.scan(/^  resources :(\w+)$/).flatten).to eq(%w[posts])
      expect(initializer.read).to include("so the menu can't place them: comments")
    end

    it "serves everything for quick, with no menu" do
      generate("--preset", "quick")

      expect(load_initializer).to have_attributes(expose: :all, implicit_defaults: :secure, require_lock: true)
      expect(menu).not_to exist
      expect(initializer.read).not_to include("TODO(setup)")
    end

    it "serves nothing for strict until a menu line is uncommented" do
      generate("--preset", "strict")

      expect(load_initializer).to have_attributes(expose: :listed, strict_defaults: true)
      expect(menu.read).to include("# resources :posts", "# page :back_office")
      expect(menu.read).not_to match(/^  resources /)
    end

    it "keeps an existing menu" do
      admin_files(menu: "ReactiveAdmin.menu { resources :posts }\n")
      output = generate

      expect(menu.read).to eq("ReactiveAdmin.menu { resources :posts }\n")
      expect(output).to match(/skip.*app\/admin\/menu\.rb/)
    end

    it "asks for the preset at a terminal" do
      answering(/start/ => "quick", /mask/ => "none", /MCP/ => "off", /switch/ => "nobody")
      generate

      expect(load_initializer.expose).to eq(:all)
    end
  end

  describe "masking" do
    before do
      root.join("db").mkpath
      root.join("db/schema.rb").write(<<~RUBY)
        create_table "patients" do |t|
          t.string "first_name"
          t.string "email"
          t.date "date_of_birth"
          t.string "ssn"
          t.string "api_token"
          t.string "encrypted_password"
          t.datetime "token_expires_at"
          t.bigint "user_id"
        end
      RUBY
      root.join("config/initializers/filter_parameter_logging.rb").write("Rails.application.config.filter_parameters += [:passw, :email, :ssn]\n")
    end

    it "proposes an identity number that ends in _id, but no foreign key" do
      root.join("db/schema.rb").write("create_table \"people\" do |t|\n  t.string \"tax_id\"\n  t.bigint \"account_id\"\nend\n")
      generate
      expect(load_initializer.masked_attributes).to eq(%i[tax_id])
    end

    it "reads only the filter list itself, and keeps proposing what it can't prove is covered" do
      root.join("config/initializers/filter_parameter_logging.rb").write(<<~RUBY)
        # Older apps also filtered :date_of_birth and "api_token".
        Rails.application.config.filter_parameters += [
          :passw, :email, # :ssn was here
          /secret/
        ]
      RUBY
      generate
      expect(load_initializer.masked_attributes).to eq(%i[date_of_birth ssn api_token])
    end

    it "proposes the secrets filter_parameters misses" do
      generate
      expect(load_initializer.masked_attributes).to eq(%i[date_of_birth api_token])
    end

    it "shows what it found and takes an edited list at a terminal" do
      answering(/start/ => "guided", /mask/ => "date_of_birth, phone", /MCP/ => "off", /switch/ => "nobody")
      output = generate

      expect(output).to include("already masked by filter_parameters: ssn, encrypted_password", "operators usually need", "first_name")
      expect(load_initializer.masked_attributes).to eq(%i[date_of_birth phone])
    end

    it "takes the list as a flag, or none" do
      generate("--mask", "mrn,dob")
      expect(load_initializer.masked_attributes).to eq(%i[mrn dob])

      initializer.delete
      generate("--no-mask")
      expect(load_initializer.masked_attributes).to eq([])
    end
  end

  describe "MCP" do
    it "stays off by default" do
      generate
      expect(load_initializer.mcp.enabled).to be(false)
    end

    it "turns on read-only or full access by flag, warning about writes" do
      generate("--mcp", "read_only")
      expect(load_initializer.mcp).to have_attributes(enabled: true, default: :read_only)

      initializer.delete
      output = generate("--mcp", "full")
      expect(load_initializer.mcp).to have_attributes(enabled: true, default: :full)
      expect(output).to include("agents can create, update and delete")
    end

    it "asks at a terminal" do
      answering(/start/ => "guided", /mask/ => "none", /MCP/ => "read_only", /switch/ => "nobody")
      generate
      expect(load_initializer.mcp.enabled).to be(true)
    end
  end

  describe "the new admin" do
    let(:dashboard) { root.join("app/admin/dashboard.rb") }
    let(:user) { Struct.new(:admin?) }

    before { admin_files(dashboard: "ActiveAdmin.register_page \"Dashboard\" do\n  content title: proc { I18n.t(\"active_admin.dashboard\") } do\n    para \"Hi\"\n  end\nend\n") }

    it "is for nobody by default, and leaves the dashboard alone" do
      before = dashboard.read
      generate

      expect(load_initializer.ui.available.call(user.new(true))).to be(false)
      expect(dashboard.read).to eq(before)
    end

    it "opens to admins and adds the switch to the dashboard, once" do
      generate("--ui", "admins")
      generate("--ui", "admins")

      available = load_initializer.ui.available
      expect([available.call(user.new(true)), available.call(user.new(false))]).to eq([true, false])
      expect(dashboard.read).to include("  content title: proc { I18n.t(\"active_admin.dashboard\") } do\n    text_node reactiveadmin_ui_toggle\n    para")
      expect(dashboard.read.scan("reactiveadmin_ui_toggle").size).to eq(1)
    end

    it "opens to everyone by flag or at a terminal" do
      answering(/start/ => "guided", /mask/ => "none", /MCP/ => "off", /switch/ => "everyone")
      generate
      expect(load_initializer.ui.available.call(Object.new)).to be(true)
    end

    it "warns where the dashboard has no content block" do
      dashboard.write("ActiveAdmin.register_page \"Dashboard\" do\nend\n")
      expect(generate("--ui", "everyone")).to include("No `content do` block opening on its own line in app/admin/dashboard.rb")
    end

    it "doesn't count a commented-out switch as installed" do
      dashboard.write(dashboard.read.sub("    para \"Hi\"\n", "    # text_node reactiveadmin_ui_toggle\n    para \"Hi\"\n"))
      generate("--ui", "everyone")

      expect(dashboard.read).to include("do\n    text_node reactiveadmin_ui_toggle\n    # text_node reactiveadmin_ui_toggle")
    end

    it "leaves a one-line content block alone and asks for a manual edit" do
      dashboard.write("ActiveAdmin.register_page \"Dashboard\" do\n  content do; para \"Hi\"; end\nend\n")
      before = dashboard.read

      expect(generate("--ui", "everyone")).to include("No `content do` block opening on its own line")
      expect(dashboard.read).to eq(before)
    end

    it "takes a block-opening line with block arguments or a comment" do
      dashboard.write("ActiveAdmin.register_page \"Dashboard\" do\n  content do |page| # landing\n    para \"Hi\"\n  end\nend\n")
      generate("--ui", "everyone")

      expect(dashboard.read).to include("content do |page| # landing\n    text_node reactiveadmin_ui_toggle\n")
    end
  end

  describe "the boot check" do
    before do
      root.join("bin").mkpath
      root.join("bin/rails").write("")
    end

    it "reports what the app serves" do
      allow_any_instance_of(described_class).to receive(:boot_report).and_return(["ReactiveAdmin serves /api/admin: 3 of 5 resources and pages exposed\n", true])
      expect(generate).to include("ReactiveAdmin serves /api/admin: 3 of 5")
    end

    it "warns when the app doesn't boot, and can be skipped" do
      allow_any_instance_of(described_class).to receive(:boot_report).and_return(["NameError: uninitialized constant Foo\n", false])
      expect(generate).to include("didn't boot", "NameError")

      expect_any_instance_of(described_class).not_to receive(:boot_report)
      generate("--skip-check")
    end

    it "runs a script that counts the exposed resources and pages" do
      script = described_class.const_get(:BOOT_CHECK)
      expect { eval(script) }.to output(/ReactiveAdmin serves \/api\/admin: \d+ of \d+ resources and pages exposed/).to_stdout # standard:disable Security/Eval
    end
  end

  it "mentions no adapter without Pundit or CanCanCan" do
    bundle("rails")
    generate
    expect(initializer.read).not_to include("PunditAdapter", "CanCanAdapter")
  end
end
