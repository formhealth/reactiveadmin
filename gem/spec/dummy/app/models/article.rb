class Article < ApplicationRecord
  self.table_name = "posts"

  belongs_to :author
  has_many :comments, foreign_key: :post_id, inverse_of: false, dependent: :destroy

  accepts_nested_attributes_for :comments, allow_destroy: true
end
