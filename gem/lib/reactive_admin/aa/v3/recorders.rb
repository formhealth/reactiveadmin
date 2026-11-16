module ReactiveAdmin
  module AA
    module V3
      # The Arbre elements that run a host block (`index`, `form`, `show`, `register_page`'s `content`) so the
      # recorders can capture what it builds. Each is an Element rather than a Context: a Context forwards
      # unknown methods to its html string, which would swallow helpers like `truncate` that blocks call.
      module Recorders
        class Element < ::Arbre::Element
          def self.build_in(assigns, view, *args) = ::Arbre::Context.new(assigns, view).insert_tag(self, *args)

          # Everything rendered into the context so far.
          def document_html = arbre_context.to_s

          private

          def add_tag(klass, *args, &) = insert_tag(klass, *args, &)

          def open_element = current_arbre_element

          def render_within(&) = within(self, &)

          def detach(element) = element.parent&.remove_child(element)
        end

        class Form < Element
          Holder = Class.new(Element)

          private

          def add_holder(&) = add_tag(Holder, &)
        end

        class Index < Element
          private

          # AA's container for a row's action links.
          def action_links(&) = table_actions(&)
        end

        # A page's content, where AA's form component builds an Arbre form rather than calling the view helper.
        class Page < Element
          def active_admin_form_for(*args, &block)
            forms = helpers.try(:reactiveadmin_page_forms) or return super
            marker = forms.node(helpers) { helpers.active_admin_form_for(*args, &block) }
            marker ? text_node(marker) : forms.suspended { super(*args, &block) }
          end
        end
      end
    end
  end
end
