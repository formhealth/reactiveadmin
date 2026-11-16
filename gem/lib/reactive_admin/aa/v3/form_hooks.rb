module ReactiveAdmin
  module AA
    module V3
      # Modules a view is extended with so Formtastic's and AA's form helpers record instead of print.
      module FormHooks
        # A page's or show's content: each form becomes a form node, or renders as markup when it can't.
        module Page
          %i[semantic_form_for active_admin_form_for].each do |helper|
            define_method(helper) do |*args, &block|
              forms = reactiveadmin_page_forms or return super(*args, &block)
              forms.node(self) { super(*args, &block) } || forms.suspended { super(*args, &block) }
            end
          end

          def reactiveadmin_page_forms = @_reactiveadmin_page_forms
        end

        # A custom template: the first form is the response, further ones are extras.
        module Template
          def semantic_form_for(*args, &block)
            state = @_reactiveadmin_template or return super
            return state.extra_form(self) { semantic_form_for(*args, &block) } if state.extra_form?

            state.record_form(self, block) { |recording| super(*args, &recording) }
          end

          # AA's version builds an Arbre form around a real builder, which the recorder can't stand in for.
          def active_admin_form_for(resource, options = {}, &block)
            state = @_reactiveadmin_template or return super
            return state.extra_form(self) { active_admin_form_for(resource, options, &block) } if state.extra_form?

            state.arbre { semantic_form_for(resource, {builder: ::ActiveAdmin::FormBuilder}.merge(options), &block) }
          end
        end
      end
    end
  end
end
