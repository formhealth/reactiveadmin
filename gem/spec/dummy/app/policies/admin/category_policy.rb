module Admin
  # Mirrors CustomAuthorizationAdapter: editors can't touch categories.
  class CategoryPolicy < DefaultPolicy
    def method_missing(name, *)
      name.end_with?("?") ? !user.editor? : super
    end

    def respond_to_missing?(name, include_private = false) = super
  end
end
