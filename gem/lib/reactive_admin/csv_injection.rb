module ReactiveAdmin
  # OWASP CSV injection: a cell that starts with one of these runs as a formula in a spreadsheet.
  # AA escapes only String cells, classic and API alike; API exports escape every cell, so a symbol
  # or any other value whose text starts this way can't slip through.
  module CsvInjection
    FORMULA_START = ["=", "+", "-", "@", "\t", "\r"].freeze
    KEY = :reactiveadmin_csv_api
    STATE = ActiveSupport::IsolatedExecutionState

    # Per request, not on the builder: one builder serves every concurrent export of its resource.
    def build(controller, csv)
      previous = STATE[KEY]
      STATE[KEY] = controller.send(:reactiveadmin_export?)
      super
    ensure
      STATE[KEY] = previous
    end

    def sanitize(content)
      return super unless STATE[KEY]

      text = content.to_s
      text.start_with?(*FORMULA_START) ? "'#{text}" : content
    end
  end
end
