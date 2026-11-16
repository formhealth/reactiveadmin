namespace :reactiveadmin do
  desc "Coverage report of the typed API and the fallback ladder. " \
    "FORMAT=json, BASELINE=file.yml (exit 1 on regressions), WRITE_BASELINE=file.yml, THRESHOLD=0.5, MAX_FALLBACK=30, SAMPLE=0"
  task doctor: :environment do
    exit(1) if ReactiveAdmin::Doctor::CLI.run.positive?
  end

  desc "Print the HTML sanitizer policy as JSON, for the client to configure DOMPurify from"
  task html_policy: :environment do
    puts JSON.pretty_generate(ReactiveAdmin::HtmlPolicy.export)
  end

  desc "Write the OpenAPI document of the full exposed admin API as YAML, for CI diffs. OUT=path overrides config.openapi.output"
  task openapi: :environment do
    Rails.application.reload_routes_unless_loaded
    warn "config.doctor_user is not set: scopes, batch actions and forms that read the current user are left out" unless ReactiveAdmin.config.doctor_user
    path = Rails.root.join(ENV["OUT"].presence || ReactiveAdmin.config.openapi.output)
    document = ReactiveAdmin::OpenApi.build(full: true)
    FileUtils.mkdir_p(path.dirname)
    File.write(path, ReactiveAdmin::OpenApi.to_yaml(document))
    puts "wrote #{path.relative_path_from(Rails.root)}"
  end
end
