class TicketSearch
  include ActiveModel::Model

  attr_accessor :term, :pick

  validates :term, presence: true

  def matches = Ticket.where("title LIKE ?", "%#{term}%").order(:id)

  # Over the inline limit once enough tickets match, so the control is a typeahead scoped by the term.
  def choices = matches.pluck(:title, :id)
end
