module ReactiveAdmin
  # Runs ActiveAdmin's configured authorization adapter for a user outside an AA controller.
  class Authorizer
    attr_reader :user

    def self.for(controller)
      method = AA.current_user_method(Registry.namespace)
      new(method && controller.send(method))
    end

    def initialize(user, namespace = Registry.namespace)
      @user = user
      @adapter = AA.authorization_adapter(namespace)
    end

    # The adapter's resource is only consulted when no subject is given.
    def authorized?(action, subject = nil, config: nil)
      @adapter.new(config, @user).authorized?(action, subject)
    end

    # Limits a relation to what the user may read; models without an AA registration are left alone.
    def scope(relation)
      config = AA.resource_for(Registry.namespace, relation.klass)
      return relation unless config

      adapter = @adapter.new(config, @user)
      return adapter.scope_collection(relation, AA::Auth::READ) if relation.limit_value

      # Pundit inspects the relation when it has no policy of its own, which would load rows.
      adapter.scope_collection(relation.limit(0), AA::Auth::READ).unscope(:limit)
    end
  end

  # Stands in for a user with every permission, for documents that describe the whole surface.
  class Authorizer::Permissive
    def user = nil

    def authorized?(*, **) = true

    def scope(relation) = relation
  end
end
