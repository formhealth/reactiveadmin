class Post < ApplicationRecord
  belongs_to :author
  belongs_to :category, optional: true
  has_many :comments, dependent: :destroy
  has_many :taggings, dependent: :destroy
  has_many :tags, through: :taggings

  enum :status, {draft: 0, published: 1, archived: 2}

  accepts_nested_attributes_for :comments, allow_destroy: true

  scope :featured, -> { where(featured: true) }

  validates :title, presence: true
end
