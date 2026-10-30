# A "new plan" form wrapped in the record's context: a heading, a table of the current plan, a notice when
# there is none, and a panel holding the inputs. All of it is content, not fields.
ActiveAdmin.register Account do
  menu false

  permit_params :author_id, :plan_id, :sponsor_id

  reactive { mask :api_token }

  form do |f|
    current = f.object.author.accounts.where.not(id: f.object.id).order(:id).last&.plan

    h3 { strong { f.object.author.name } }

    div do
      div do
        if current
          panel("Current Plan") do
            attributes_table_for current do
              row :name
              row :api_token
              row("Notes") { |plan| raw(plan.notes) }
              row("Remove") { link_to "Remove", admin_author_path(f.object.author), method: :delete, data: {confirm: "Remove it?"} }
            end
          end

          panel("New Plan") do
            inputs do
              input :author_id, as: :hidden
              input :plan_id, label: "Plan", as: :select, collection: Plan.order(:name).pluck(:name, :id)
              input :sponsor_id, as: :select, collection: Author.order(:name).pluck(:name, :id)
            end
          end
        else
          para "Current plan required"
        end
      end
    end
  end

  controller do
    def new = super { resource.author = Author.order(:id).first }
  end
end
