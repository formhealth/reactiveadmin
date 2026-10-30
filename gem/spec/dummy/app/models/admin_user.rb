class AdminUser < ApplicationRecord
  belongs_to :author, optional: true

  accepts_nested_attributes_for :author, update_only: true

  def editor? = role == "editor"
end
