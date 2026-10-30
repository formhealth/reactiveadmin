ActiveAdmin.register_page "Ticket Report" do
  menu false

  content do
    search = TicketSearch.new(params.fetch(:report, {}).permit(:term, :pick))
    active_admin_form_for search, as: :report, url: admin_ticket_report_path, method: :get do |f|
      f.inputs do
        f.input :term, as: :string
        f.input :pick, as: :select, collection: search.choices
      end
      f.actions { f.action :submit, label: "Run report" }
    end

    if search.term.present?
      panel "Matches" do
        table_for(search.matches.limit(5)) { column :title }
      end
    end
  end
end
