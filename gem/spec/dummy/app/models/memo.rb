class Memo < ApplicationRecord
  belongs_to :author, optional: true

  encrypts :secret
  enum :priority, {low: 0, high: 1}
end
