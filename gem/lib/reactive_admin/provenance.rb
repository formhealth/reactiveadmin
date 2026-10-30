module ReactiveAdmin
  # Tells markup the host's DSL produced from markup a stored value carried in. Inside a scope, the view's
  # `link_to`, `button_to` and form helpers stamp the anchor or form they return with a random per-request
  # secret; the walker turns only stamped controls into actions and stamped forms into frames. Stored text
  # (Markdown, `simple_format(notes)`) can't know the secret, so its `data-method` links and forms stay inert.
  module Provenance
    ATTRIBUTE = "data-reactiveadmin-origin".freeze
    UNSTAMPED_TAG = /\A<(a|form)\b(?![^>]*#{ATTRIBUTE})/
    KEY = :reactiveadmin_provenance
    STATE = ActiveSupport::IsolatedExecutionState

    module_function

    def with_scope
      previous = STATE[KEY]
      STATE[KEY] = SecureRandom.hex(16)
      yield
    ensure
      STATE[KEY] = previous
    end

    def trusted?(el)
      secret = STATE[KEY]
      !secret.nil? && ActiveSupport::SecurityUtils.secure_compare(el[ATTRIBUTE].to_s, secret)
    end

    def stamp(html)
      secret = STATE[KEY]
      return html unless secret && html.html_safe?

      html.sub(UNSTAMPED_TAG) { %(#{$&} #{ATTRIBUTE}="#{secret}") }.html_safe
    end

    # Prepended to Arbre's tags: an `a` or `form` built in the DSL is the host's, unlike a string inserted as text.
    module Tags
      def build(*)
        super
        secret = STATE[KEY]
        set_attribute(ATTRIBUTE, secret) if secret && tag_name.in?(%w[a form])
      end
    end

    # Prepended to ActionView::Base, ahead of UrlHelper.
    module Helpers
      def link_to(...) = Provenance.stamp(super)

      def button_to(...) = Provenance.stamp(super)

      private

      # form_for, form_with and form_tag all build their form through one of these.
      def form_tag_html(...) = Provenance.stamp(super)

      def form_tag_with_body(...) = Provenance.stamp(super)
    end
  end
end
