class Account < ApplicationRecord
  belongs_to :author
  belongs_to :plan, optional: true
  belongs_to :sponsor, class_name: "Author", optional: true
end
