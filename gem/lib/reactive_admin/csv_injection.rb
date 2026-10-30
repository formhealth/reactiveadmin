module ReactiveAdmin
  # OWASP CSV injection: a cell that starts with one of these runs as a formula in a spreadsheet.
  # AA escapes only String cells, classic and API alike; API exports escape every cell, so a symbol
  # or any other value whose text starts this way can't slip through.
  module CsvInjection
    FORMULA_START = ["=", "+", "-", "@", "\t", "\r"].freeze

    def build(controller, csv)
      @reactiveadmin_api = controller.send(:reactiveadmin_export?)
      super
    end

    def sanitize(content)
      return super unless @reactiveadmin_api

      text = content.to_s
      text.start_with?(*FORMULA_START) ? "'#{text}" : content
    end
  end
end
