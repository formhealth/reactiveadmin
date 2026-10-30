module ReactiveAdmin
  # A date input's `min` or `max` as the client takes it: an ISO day for a date control, an ISO time for a
  # datetime one. Accepts what a host gives `input_html:` or jQuery UI's `datepicker_options`: a Date or
  # Time, an ISO string, a number of days from today, or a relative string such as "+1m +7d".
  module DateBound
    RELATIVE = /\A\s*(?:[+-]?\d+\s*[dwmy]\s*)+\z/i
    UNITS = {"d" => :days, "w" => :weeks, "m" => :months, "y" => :years}.freeze

    module_function

    def call(value, control)
      time = resolve(value) or return
      (control == "date") ? time.to_date.iso8601 : time.iso8601
    end

    def resolve(value)
      case value
      when Date, Time then value.in_time_zone
      when Integer then Date.current.advance(days: value).in_time_zone
      when String then value.match?(RELATIVE) ? relative(value).in_time_zone : Time.zone.parse(value)
      end
    rescue ArgumentError, RangeError
      nil
    end

    def relative(text)
      steps = text.scan(/([+-]?\d+)\s*([dwmy])/i).each_with_object(Hash.new(0)) { |(n, unit), sum| sum[UNITS.fetch(unit.downcase)] += n.to_i }
      Date.current.advance(steps)
    end
  end
end
