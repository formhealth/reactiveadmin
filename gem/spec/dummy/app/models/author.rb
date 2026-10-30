class Author < ApplicationRecord
  has_many :posts, dependent: :destroy
  has_many :memos, dependent: :nullify
  has_one :profile, dependent: :destroy
  has_many :accounts, dependent: :destroy

  accepts_nested_attributes_for :profile, update_only: true

  validates :name, presence: true
end
