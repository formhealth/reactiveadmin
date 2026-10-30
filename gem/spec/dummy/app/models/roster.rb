class Roster < ApplicationRecord
  # A form-only row of a repeated group; the rows live in the json columns, keyed by their index.
  class Contact
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :email, :string
    attribute :role, :string
  end

  def contact(column, index) = Contact.new((public_send(column) || {}).fetch(index.to_s, {}).slice("email", "role"))
end
