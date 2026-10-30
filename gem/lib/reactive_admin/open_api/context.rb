module ReactiveAdmin
  module OpenApi
    # Who the document is for and how each resource is probed. Probes are controllers of the resource,
    # outside a request, bound to the user, so AA's procs (`if:`, scopes, filters) answer as they would for them.
    class Context
      Host = Struct.new(:controller)

      attr_reader :user, :ids

      # `controller` is the request's own when there is one (the endpoint); otherwise a stand-in.
      def initialize(user, controller:, full:)
        @user = user
        @full = full
        @probes = {}
        @ids = OperationIds.new
        @controller = controller || Doctor::Sample.new(Host.new(ManifestController), view_user).controller
      end

      def full? = @full

      def authorizer = @authorizer ||= @full ? Authorizer::Permissive.new : Authorizer.for(@controller)

      def manifest = @manifest ||= Manifest.new(@controller, authorizer:)

      # The summaries of the resources the user may open (what `_manifest` lists), built once.
      def resources = @resources ||= manifest.resources

      def probe(config) = (@probes[config] ||= Doctor::Sample.new(config, view_user).tap { permit_everything(it.controller) if @full })

      # Whether the user may do `action` to the resource or page; anything that raises is denied.
      def authorized?(action, subject, config)
        authorizer.authorized?(action, subject, config:)
      rescue
        false
      end

      private

      # Views ask their controller before showing a batch action or a link; a full document shows them all.
      def permit_everything(controller) = controller.define_singleton_method(:authorized?) { |*| true }

      # A full document has no user; probes still need one for procs that read it.
      def view_user = @full ? ReactiveAdmin.config.doctor_user&.call : @user
    end
  end
end
