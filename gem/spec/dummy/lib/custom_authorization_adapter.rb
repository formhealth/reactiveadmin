# Nobody may destroy posts; editors only see and change their own author's posts, can't import
# them and can't touch categories.
class CustomAuthorizationAdapter < ActiveAdmin::AuthorizationAdapter
  def authorized?(action, subject = nil)
    case subject
    when normalized(Category)
      return !user&.editor?
    when normalized(Post)
      return false if action == ActiveAdmin::Auth::DESTROY
      return !user&.editor? if action == :import
      return owned?(subject) if subject.is_a?(Post)
    end
    true
  end

  def scope_collection(collection, action = ActiveAdmin::Auth::READ)
    klass = collection.respond_to?(:klass) ? collection.klass : collection
    return collection unless klass == Post && user&.editor?

    collection.where(author_id: user.author_id)
  end

  private

  def owned?(post) = post.new_record? || !user&.editor? || post.author_id == user.author_id
end
