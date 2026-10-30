module Admin
  # Mirrors CustomAuthorizationAdapter: only admins destroy and import; editors only reach their own
  # author's posts, custom actions included.
  class PostPolicy < DefaultPolicy
    def destroy? = user.role == "admin"

    def destroy_all? = destroy?

    def import? = !user.editor?

    def method_missing(name, *)
      name.end_with?("?") ? owned? : super
    end

    def respond_to_missing?(name, include_private = false) = super

    private

    def owned? = !record.is_a?(Post) || record.new_record? || !user.editor? || record.author_id == user.author_id

    class Scope < DefaultPolicy::Scope
      def resolve = @user.editor? ? @scope.where(author_id: @user.author_id) : @scope
    end
  end
end
