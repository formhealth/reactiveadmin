module ReactiveAdmin
  # Wiring for `as: :typeahead` and `source:` in the classic admin's Formtastic inputs.
  module Typeahead
    # Mixed into inputs: a `source:` replaces `collection:` with the source's whole (scoped) list,
    # which keeps the classic markup identical to a hand-built datalist.
    module SourceCollection
      def collection
        return super unless options[:source]

        Choices.source(options[:source], template, scope: options[:scope], object: scope_object).pairs
      end

      # Inside has_many the block receives the parent form object, as the child's own is blank.
      def scope_object = (builder.options[:parent_builder] || builder).object
    end

    def self.install
      AA.extend_resource(dsl: ResourceDSL, config: ResourceOptions)
      AA.install_typeahead(SourceCollection)
    end
  end

  class << self
    # Register once, in the host: `ReactiveAdmin.option_sources { source :users, -> { User.all }, label: :title }`.
    def option_sources(&block)
      @option_sources ||= OptionSources.new
      @option_sources.instance_exec(&block) if block
      @option_sources
    end

    def diagnostics = @diagnostics ||= Diagnostics.new
  end
end
