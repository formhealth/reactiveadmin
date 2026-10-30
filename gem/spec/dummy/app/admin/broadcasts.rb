ActiveAdmin.register_page "Broadcasts" do
  menu false

  # Echoes what arrived, so specs can see how params were shaped.
  page_action :announce, method: :post do
    received = params.require(:broadcast).permit(:subject, :body, :urgent, :audience, :region, tags: []).to_h
    return redirect_to admin_broadcasts_path, alert: "Subject can't be blank" if received[:subject].blank?

    redirect_to admin_broadcasts_path, notice: received.to_json
  end

  page_action :note, method: :post do
    redirect_to admin_broadcasts_path, notice: params.require(:quick).permit(:note).to_h.to_json
  end

  content do
    panel "Announce" do
      render partial: "admin/broadcasts/announce"
    end

    panel "Quick note" do
      active_admin_form_for :quick, url: admin_broadcasts_note_path, method: :post do |f|
        f.inputs do
          f.input :note, hint: "Seen by everyone"
        end
        f.actions do
          f.action :submit, label: "Save note", button_html: {data: {confirm: "Post this note?"}}
        end
      end
    end
  end
end
