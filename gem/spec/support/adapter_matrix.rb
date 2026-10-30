# The suite runs once per AUTH_ADAPTER (default, custom, pundit). Examples describe the
# adapter-dependent outcome through these helpers instead of branching inline.
module AdapterMatrix
  ADAPTER = ENV.fetch("AUTH_ADAPTER", "default")

  def adapter = ADAPTER

  def adapter?(*names) = names.map(&:to_s).include?(ADAPTER)

  def postgres? = ActiveRecord::Base.connection.adapter_name.match?(/postg/i)

  # default allows everything; custom denies everyone; pundit allows admins.
  def can_destroy_post?(user)
    case ADAPTER
    when "default" then true
    when "custom" then false
    else user.role == "admin"
    end
  end

  def can_import_posts?(user) = ADAPTER == "default" || !user.editor?

  def can_read_categories?(user) = ADAPTER == "default" || !user.editor?

  # custom and pundit scope editors to their author's posts.
  def can_see_post?(user, post) = ADAPTER == "default" || !user.editor? || post.author_id == user.author_id

  # A gap in the gem, tracked by a WP id. The example still runs: it is reported as pending while
  # it fails and passes once fixed. STRICT_GAPS=1 turns a fixed gap into a failure so stale markers
  # get removed.
  def known_gap(reason)
    if ENV["STRICT_GAPS"]
      pending(reason)
      yield
    else
      begin
        yield
      rescue Exception => e # standard:disable Lint/RescueException
        raise if e.is_a?(RSpec::Core::Pending::SkipDeclaredInExample)

        pending(reason)
        raise
      end
    end
  end
end
