module ReactiveAdmin
  # What error reporters see in place of an unexpected exception: the original's message can carry
  # record data (a failed SQL statement, a validation value), so only its class, where it was raised
  # and the request it came from are passed on.
  class ScrubbedError < StandardError
    attr_reader :original_class

    def self.report(exception, resource:, action:, request_id:)
      error = new(exception, resource:, action:)
      context = {resource:, action:, request_id:, error_class: error.original_class}
      ReactiveAdmin.config.error_reporter.call(error, context)
    rescue => e
      Rails.logger.error("[reactiveadmin] error reporter failed: #{e.class}")
    end

    def initialize(original, resource: nil, action: nil)
      @original_class = original.class.name
      super("#{original_class} in #{resource}##{action}")
      set_backtrace(original.backtrace)
    end
  end
end
