# Repeated nested groups that are not associations: rows are told apart by `index:`, or by a `name][i` hack.
ActiveAdmin.register Roster do
  menu false

  permit_params :name, :starts_on, :signed_on, :ends_at, contacts: [:email, :role], backups: [:email, :role]

  form do |f|
    f.inputs do
      f.input :name
      f.input :starts_on, as: :date_picker, input_html: {min: Date.new(2026, 1, 1), max: "2026-12-31"}
      f.input :signed_on, as: :datepicker, datepicker_options: {min_date: "2026-01-01", max_date: Date.new(2026, 6, 30)}
      f.input :ends_at, as: :datetime_picker, input_html: {min: Time.utc(2026, 3, 1, 9)}
    end
    3.times do |i|
      f.semantic_fields_for :contacts, f.object.contact(:contacts, i), index: i do |row|
        row.inputs "Contact #{i + 1}" do
          row.input :email
          row.input :role, as: :select, collection: %w[primary backup]
        end
      end
    end
    2.times do |i|
      f.semantic_fields_for "backups][#{i}", f.object.contact(:backups, i) do |row|
        row.inputs "Backup #{i + 1}" do
          row.input :email
          row.input :role, input_html: {disabled: true}
        end
      end
    end
    f.actions
  end
end
