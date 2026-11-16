require "cgi"
require "digest"

module ReactiveAdmin
  module Fixtures
    # Replaces what a payload says about records with deterministic fakes of the same shape, and
    # keeps what it says about the admin itself. Default deny: a string stays only under a key known
    # to be structural (types, keys, params, labels the host wrote, enum choices); every other
    # string is fake, so a payload field this class has never heard of can't leak. Masked nodes stay
    # masked. Fakes derive from a digest of the original, so equal inputs give equal outputs across
    # runs and files, and ids stay consistent between a row, its paths, refs and option lists.
    class Scrubber
      WORDS = %w[lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua
        enim minim veniam quis nostrud exercitation ullamco laboris nisi aliquip ex ea commodo consequat duis aute irure in reprehenderit
        voluptate velit esse cillum fugiat nulla pariatur excepteur sint occaecat cupidatat non proident sunt culpa qui officia deserunt
        mollit anim id est laborum].freeze

      # Strings under these keys describe the admin, never a record.
      KEEP = %w[type kind key name param param_key control method variant presentation mode placement resource align sort_key tone direction
        display justify breakpoint width max_width text_align tag language mime class_name custom_key api_guard field as default_order
        default_scope current_scope order sortable view group page from to code locale time_zone date_format datetime_format layout icon parent
        actions marks index_views download_formats trusted_media_hosts jsonrpc].to_set.freeze
      # Written by the host (labels, confirmations, hints); dropped when they quote a record value.
      TEXTS = %w[label title description hint placeholder plural_label menu_parent new_record_label submit_label submit_confirm confirm
        disabled_reason row_actions_label unsupported_reason footer headers reason where].to_set.freeze
      PATHS = %w[href url api_path path meta_path options_path expand_path form_path classic_url show edit api_show api_edit
        index_path_template api_index_path_template title_link title_image favicon src].to_set.freeze
      INPUT_LIMITS = %w[step maxlength rows].to_set.freeze
      RECORD_LIMITS = %w[min max].to_set.freeze
      ROW_TEXTS = %w[label confirm disabled_reason].to_set.freeze
      QUERY_CONTEXTS = %w[filter form page_form template].to_set.freeze
      BOOLEAN_CHOICES = %w[Yes No true false].to_set.freeze
      NUMERIC_QUERY_KEYS = %w[page per_page form].to_set.freeze
      # Query names the API, ActiveAdmin and Active Storage read; any other name can be record data (`?alice%40private.test=1`).
      QUERY_NAMES = %w[
        as batch_action batch_action_inputs classic collection_selection commit context cursor disposition embed field form format
        id ids limit locale order page path per_page q scope term token value view
      ].to_set.freeze
      QUERY_NAME = /\A(?<base>[a-z_]+)(?:\[[a-z0-9_]*\])*\z/
      FORM_CONTROLS = %w[form input select textarea button].to_set.freeze
      CSS_TOKEN = /\A-?[a-z_][a-z0-9_-]*\z/i
      CSS_PROPERTY = /\A[a-z][a-z-]*\z/
      CSS_VALUE = /\A[#a-z0-9\s.,%()+-]+\z/i
      FORM_METHODS = %w[get post put patch delete dialog].to_set.freeze
      FORM_ENCODINGS = %w[application/x-www-form-urlencoded multipart/form-data text/plain].to_set.freeze
      # Attributes holding element ids: one, or a space-separated list (aria-labelledby).
      HTML_ID_REFS = %w[id for list form aria-labelledby aria-describedby aria-controls aria-owns].to_set.freeze
      HTML_ELEMENTS = %w[a abbr address area article aside audio b bdi bdo blockquote br button canvas caption cite code col colgroup
        data datalist dd del details dfn dialog div dl dt em fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 header hgroup hr i img
        input ins kbd label legend li main map mark menu meter nav ol optgroup option output p picture pre progress q rp rt ruby s samp
        search section select slot small source span strong sub summary sup table tbody td template textarea tfoot th thead time tr track u
        ul var video wbr].to_set.freeze
      # Attributes whose values come from a fixed vocabulary keep a value only when it's in that vocabulary;
      # anything else (target="Jane") is record data like any other attribute.
      ENUM_ATTRIBUTES = {
        "type" => %w[text password email number tel url search date time datetime-local month week color range checkbox radio file hidden submit reset button image 1 a A i I],
        "autocomplete" => %w[on off name honorific-prefix given-name additional-name family-name honorific-suffix nickname email username new-password current-password one-time-code organization-title organization street-address address-line1 address-line2 address-line3 address-level1 address-level2 address-level3 address-level4 country country-name postal-code cc-name cc-given-name cc-family-name cc-number cc-exp cc-exp-month cc-exp-year cc-csc cc-type transaction-currency transaction-amount language bday bday-day bday-month bday-year sex tel tel-country-code tel-national tel-area-code tel-local tel-extension impp url photo shipping billing home work mobile fax pager webauthn],
        "inputmode" => %w[none text decimal numeric tel search email url],
        "role" => %w[alert alertdialog application article banner button cell checkbox columnheader combobox complementary contentinfo definition dialog directory document feed figure form grid gridcell group heading img link list listbox listitem log main marquee math menu menubar menuitem menuitemcheckbox menuitemradio navigation none note option presentation progressbar radio radiogroup region row rowgroup rowheader scrollbar search searchbox separator slider spinbutton status switch tab table tablist tabpanel term textbox timer toolbar tooltip tree treegrid treeitem],
        "dir" => %w[ltr rtl auto],
        "align" => %w[left right center justify top middle bottom baseline],
        "target" => %w[_blank _self _parent _top],
        "rel" => %w[alternate author bookmark external help license next nofollow noopener noreferrer opener prev search tag ugc sponsored stylesheet icon preload prefetch preconnect dns-prefetch modulepreload manifest canonical],
        "open" => %w[open]
      }.transform_values(&:to_set).freeze
      # Record html keeps only attribute names HTML defines; `data-patient-jane-doe` can name a record.
      HTML_ATTRIBUTES = %w[
        abbr accept accesskey action align alt autocomplete autofocus bgcolor border cellpadding cellspacing checked cite class
        color cols colspan content contenteditable controls coords datetime decoding default dir disabled download draggable
        enctype for form headers height hidden high href hreflang id inputmode label lang list loading loop low max maxlength
        media method min minlength multiple muted name nowrap open optimum pattern placeholder poster preload readonly rel
        required reversed role rows rowspan scope selected shape size sizes span spellcheck src srclang srcset start step style
        summary tabindex target title translate type valign value width wrap
        aria-checked aria-controls aria-current aria-describedby aria-disabled aria-expanded aria-haspopup aria-hidden
        aria-label aria-labelledby aria-live aria-pressed aria-selected
      ].to_set.freeze
      NUMERIC_ATTRIBUTES = %w[colspan rowspan width height start].to_set.freeze
      NUMERIC_ATTRIBUTE = /\A\d{1,4}(?:%|px)?\z/
      LANGUAGE = /\A[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*\z/

      UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
      DIGITS = /\A\d+\z/
      INTEGER_ID = /\A-?\d+\z/
      EMAIL = /\A[^@\s<>]+@[^@\s<>]+\z/
      NUMBERLIKE = /\A[\d.,\s$%+-]*\d[\d.,\s$%+-]*\z/
      TIME = /\A(\d{4}-\d{2}-\d{2})(?:([T ])(\d{2}:\d{2}(?::\d{2})?)(\.\d+)?(Z|[+-]\d{2}:?\d{2})?)?\z/
      TIME_OF_DAY = /\A\d{2}:\d{2}(?::\d{2}(\.\d+)?)?\z/
      FILE_EXTENSIONS = %w[png jpg jpeg gif webp svg avif pdf csv txt json xml zip doc docx xls xlsx ppt pptx mp3 mp4 mov wav].to_set.freeze
      MIN_LENGTH = 4
      MIN_QUOTE = 2
      MAX_WORDS = 120
      MAX_KEPT_LIMIT = 9_999
      MAX_TICKS = 100_000
      # The route templates Paths emits; any other braced or colon segment is opaque record data.
      PLACEHOLDERS = [Paths::PARENT_ID, ":id"].to_set.freeze
      ID_RETRIES = 20
      MAX_SALTS = 32

      # vocabulary: each resource's enum names by attribute ({"posts" => {"status" => %w[draft published]}}), kept only
      # as choices of that attribute (its options, its status tags), so a record's "White" isn't kept by another enum.
      # routes: the literal segments of the app's routes; every other path segment is opaque and faked.
      # seed: the app's private seed (Fixtures.seed). Every fake, and every date and number offset, derives from it,
      # so a fixture can't be reversed without it; there is no public default to fall back on.
      def self.numeric?(value) = value.is_a?(Numeric) || (value.is_a?(String) && value.match?(/\A-?\d+(?:\.\d+)?\z/))

      def initialize(seed:, vocabulary: {}, routes: [])
        raise ArgumentError, "a private seed is required" if seed.to_s.empty?

        @vocabulary = vocabulary.to_h { |resource, enums| [resource.to_s, enums.to_h { |attribute, names| [attribute.to_s, choices_of(names)] }] }
        @scope = BOOLEAN_CHOICES
        @routes = routes.to_set
        @seed = seed
        @ids = {}
        @taken = Set.new
        @choices = {}
        @taken_choices = @vocabulary.values.flat_map(&:values).reduce(BOOLEAN_CHOICES, :|).dup
        @originals = Set.new
        @pattern = nil
        @key_pattern = nil
        @keys = {}
        @taken_keys = Set.new
        @varying = Set.new
        @known = Hash.new { |hash, key| hash[key] = Set.new }
        @kept = Set.new
        @html_ids = {}
        @real_ids = Set.new
        @varying_keys = Set.new
        @taken_html_ids = Set.new
      end

      # Host-written strings the last scrub kept verbatim, for a person to review.
      def kept = @kept.sort

      # entries: [[kind, payload], ...] with kind :manifest, :meta, :index, :show or :form. Scrubs them
      # together so ids and fakes agree across payloads.
      def scrub_all(entries)
        @learning = true
        entries.each { |kind, payload, resource| within(resource) { walk(payload, root: kind) } }
        @learning = false
        @kept.clear
        quoted = @originals.select { it.size >= MIN_QUOTE }.sort_by { -it.size }
        long, short = quoted.partition { it.size >= MIN_LENGTH }
        # Short values only count as whole tokens, so "Amy" is found in "Delete Amy?" but not in "Amyloid".
        parts = [(Regexp.union(long).source if long.any?), ("(?<![[:alnum:]])(?:#{Regexp.union(short).source})(?![[:alnum:]])" if short.any?)].compact
        @pattern = Regexp.new(parts.join("|"), Regexp::IGNORECASE) if parts.any?
        normalized = quoted.filter_map { normalize(it).presence }.uniq
        @key_pattern = /(?<![a-z0-9])(?:#{Regexp.union(normalized).source})(?![a-z0-9])/ if normalized.any?
        entries.map { |kind, payload, resource| within(resource) { walk(payload, root: kind) } }
      end

      private

      def walk(node, key = nil, root: nil, parent: nil)
        case node
        when Hash then hash(node, root:)
        when Array then node.map { walk(it, key, parent:) }
        when String then string(node, key, parent, root)
        else node
        end
      end

      def hash(node, root: nil)
        return node if node["type"] == "masked"

        learn(node) if @learning
        return field(node) if node.key?("control") && (node.key?("param") || node.key?("name"))
        return option(node) if option?(node)

        node.to_h do |key, value|
          [key, case key
                when "value", "summary" then data_value(node, key, value)
                when "id" then value.is_a?(Integer) ? integer_id(value) : walk(value, key, parent: node, root: (root if value.is_a?(String)))
                when "params" then params(value)
                when "rows" then (node["type"] == "definition_list") ? definition_rows(value) : rows(value, node)
                when "cells" then cells(value, node)
                when "scopes" then scopes(value)
                else walk(value, key, parent: node, root: (root if value.is_a?(String)))
                end]
        end
      end

      # Query values a path may keep: the scopes, orders, fields and views the payloads declare.
      def learn(node)
        @known["scope"].merge(Array(node["scopes"]).filter_map { it["id"] if it.is_a?(Hash) })
        @known["order"].merge(Array(node["columns"]).filter_map { it["sort_key"] if it.is_a?(Hash) }.product(%w[asc desc]).map { it.join("_") })
        @known["as"].merge(Array(node["index_views"]).filter_map { it["as"] if it.is_a?(Hash) })
        @known["format"].merge(Array(node["download_formats"]))
        {"scope" => %w[default_scope current_scope], "order" => %w[default_order order], "view" => %w[view], "field" => %w[name]}.each do |query, keys|
          next if query == "field" && !node.key?("control")

          @known[query].merge(node.values_at(*keys).grep(String))
        end
        # Paths the API builds name the field they read (`field=comments.author` for a nested typeahead).
        node.values_at("options_path", "expand_path").grep(String).each do |trusted|
          field = query_field(trusted)
          @known["field"] << field if field.is_a?(String) && field.present?
        end
      end

      # A query it can't decode names no field; the path itself is still scrubbed like any other.
      def query_field(path)
        Rack::Utils.parse_query(path.split("?", 2)[1].to_s)["field"]
      rescue Rack::QueryParser::InvalidParameterError, ArgumentError
        nil
      end

      # A scope's id names a declared scope, so it stays even when it looks like a record id ("1"), which keeps
      # default_scope and current_scope pointing at it.
      def scopes(value)
        return walk(value, "scopes") unless value.is_a?(Array)

        value.map do |scope|
          next walk(scope, "scopes") unless scope.is_a?(Hash)

          # The id names the scope; its name and label are display text, quote-checked and listed for review.
          scope.to_h do |key, item|
            [key, if key == "id" then item
                  elsif %w[name label].include?(key) && item.is_a?(String) && !item.empty? then text(item)
                  else walk(item, key, parent: scope)
                  end]
          end
        end
      end

      # What differs between rows (a row_class, an action's label) comes from the record, not the host.
      def rows(value, node)
        if value.is_a?(Array) && value.all?(Hash)
          varying(value.map { it["class_name"] })
          by_key = value.flat_map { Array(it["actions"]).grep(Hash) }.group_by { it["key"] }.values
          # A label-derived key (ActionLinks: "Call Bob" -> call_bob) differs per row, so the same slot is compared too.
          by_slot = value.map { Array(it["actions"]).grep(Hash) }.then { |slots| (0...slots.map(&:size).max.to_i).map { |i| slots.filter_map { it[i] } } }
          (by_key + by_slot).each do |actions|
            ROW_TEXTS.each { |key| varying(actions.map { it[key] }) }
            @varying_keys.merge(actions.filter_map { it["key"] }) if actions.map { it["key"] }.uniq.size > 1
          end
        end
        return attribute_rows(value, node) if node["type"] == "attributes_table" && value.is_a?(Array)

        walk(value, "rows", parent: node)
      end

      def varying(values) = (@varying.merge(values.grep(String)) if values.uniq.size > 1)

      # A definition list comes from stored html, so its terms are record data, unlike an attributes table's labels.
      def definition_rows(rows)
        rows.map { |row| row.to_h { |key, value| [key, (key == "label") ? data(value) : walk(value, key, parent: row)] } }
      end

      # Keyed by column name, so a column called `value` or `params` is not that payload key.
      def cells(value, parent) = value.is_a?(Hash) ? value.to_h { |column, cell| [column, showing(column) { walk(cell, "cells", parent:) }] } : walk(value, "cells", parent:)

      # An attributes table row names its attribute only by its label ("Status").
      def attribute_rows(rows, node)
        rows.map do |row|
          label = row["label"] if row.is_a?(Hash)
          attribute = @vocabulary.fetch(@resource, {}).keys.find { [it.humanize, it.titleize].include?(label) }
          showing(attribute) { walk(row, "rows", parent: node) }
        end
      end

      # A status tag keeps its label only as a name of the enum its column shows, and only if it quotes no record.
      def status_label(value)
        choices = BOOLEAN_CHOICES | @vocabulary.dig(@resource, @showing.to_s).to_a
        return data(value) unless choices.include?(value)

        @pattern&.match?(value) ? fake(value) : value
      end

      def showing(attribute)
        was, @showing = @showing, attribute
        yield
      ensure
        @showing = was
      end

      # Hidden fields of a navigating action: the names are the host's, the values are not.
      def params(value) = value.is_a?(Hash) ? value.transform_values { data_value(nil, nil, it) } : walk(value, "params")

      def option?(node) = node.key?("label") && node.key?("value") && !node.key?("type") && !node["value"].is_a?(Array) && !node["value"].is_a?(Hash)

      def option(node)
        node.to_h do |key, value|
          [key, case key
                when "label" then (vocabulary?(node["value"]) && !record_id?(node["value"])) ? enum(value) : data(value)
                when "hint" then data(value)
                when "value" then option_value(value)
                else walk(value, key, parent: node)
                end]
        end
      end

      def option_value(value)
        return value unless value.is_a?(String)

        (real_id?(value) || id_like?(value)) ? id(value) : choice(value)
      end

      # Selects and checkboxes tell choices apart by value, so two choices never share a fake.
      def choice(value)
        return value if value.empty? || value == ValuePayload::MASK || vocabulary?(value)

        @choices[value] ||= begin
          fake = data(value)
          attempt = 0
          fake = "#{data(value)} #{attempt += 1}" until @taken_choices.add?(fake)
          fake
        end
      end

      def field(node)
        # A hidden foreign key (author_id) names a record, so it gets the same fake as that record everywhere.
        return hidden_id(node) if node["control"] == "hidden" && (node["name"] == "id" || node["name"].to_s.end_with?("_id"))

        values = Array(node["options"]).filter_map { it["value"] if it.is_a?(Hash) }.to_set
        choices = BOOLEAN_CHOICES | @vocabulary.dig(@resource, node["name"].to_s).to_a
        with_scope(choices) { with_interval(interval(node)) { field_keys(node, values) } }
      end

      def field_keys(node, values)
        bounds = number_bounds(node)
        node.to_h do |key, value|
          [key, case key
                when "value"
                  if @interval&.key?(key) then @interval[key]
                  elsif bounds then bounded_number(value, *bounds)
                  else fit_length(field_value(value, values), node["input_html"], value)
                  end
                when "options" then value.map { walk(it, key, parent: node) }
                when "summary" then data_value(node, key, value)
                when "input_html" then input_html(value, node["param"])
                else walk(value, key, parent: node)
                end]
        end
      end

      # A min or max can come from the record (a date it can't precede); one that every form agrees on can't.
      def input_html(value, param)
        return walk(value, "input_html") unless value.is_a?(Hash)

        value.to_h do |name, limit|
          [name, if RECORD_LIMITS.include?(name) then record_limit(param, name, limit)
                 elsif INPUT_LIMITS.include?(name) then limit
                 else walk(limit, name, parent: value)
                 end]
        end
      end

      # A min or max can come from the record (`min: current_admin_user.birth_date`) however many forms agree on
      # it, so only a small whole number (a quantity's bounds) is kept; dates and the rest are faked and learned.
      def record_limit(param, name, limit)
        return @interval[name] if @interval&.key?(name)

        structural_limit?(limit) ? limit : data_value(nil, nil, limit)
      end

      def structural_limit?(limit) = limit.is_a?(Integer) ? limit.abs <= MAX_KEPT_LIMIT : limit.is_a?(String) && limit.match?(/\A-?\d{1,4}\z/)

      # `f.input :id, as: :hidden` can carry the id as an Integer; it gets the same mapping as the string form.
      def hidden_id(node)
        node.to_h do |key, value|
          [key, if key != "value" then walk(value, key, parent: node)
                elsif value.is_a?(Integer) then integer_id(value)
                elsif value.is_a?(String) && !value.empty? then id(value)
                else value
                end]
        end
      end

      def field_value(value, options)
        case value
        when Array then value.map { field_value(it, options) }
        when String then options.include?(value) ? option_value(value) : data(value)
        else data_value(nil, nil, value)
        end
      end

      def string(value, key, parent, root)
        return value if value.empty?
        return path(value) if PATHS.include?(key)
        return action_key(value) if key == "key" && parent&.key?("kind")
        return data(value) if @varying.include?(value) && (ROW_TEXTS.include?(key) || key == "class_name")
        return row_class(value) if key == "class_name"
        return value if KEEP.include?(key)
        return identifier_id(value, parent) if key == "id"
        return data(value) if root == :show && key == "title"
        return data(value) if html_derived?(key, parent)
        return text_of(value, key, parent) if TEXTS.include?(key)
        return host_markup { data(value) } if key == "html" && %w[frame html].include?(parent&.[]("type"))

        data(value)
      end

      # Only markup the host renders (frame and html nodes) keeps its structural attributes. Html inside a record
      # value, a json value included, is record data: every attribute value is faked.
      def host_markup
        was, @host_markup = @host_markup, true
        yield
      ensure
        @host_markup = was
      end

      # A row_class can be built from the record ("customer-#{record.email}"), even when only one row was sampled.
      def row_class(value)
        return fake(value) if quotes_original?(value)

        @kept << value unless @learning
        value
      end

      def quotes_original?(value) = @pattern&.match?(value) || @key_pattern&.match?(normalize(value))

      # "Jane Doe", "jane-doe" and "jane_doe" all read as jane_doe.
      def normalize(value) = value.parameterize(separator: "_").tr("-", "_")

      # Nodes built from stored html carry its text in titles and headers.
      def html_derived?(key, parent)
        (key == "title" && %w[text document iframe].include?(parent&.[]("type"))) || (key == "headers" && parent&.[]("type") == "table")
      end

      # ActionLinks derives a link's key from its label when the host gave none, so it can quote a record.
      def action_key(value) = (@varying_keys.include?(value) || @key_pattern&.match?(value)) ? slug(value).tr("-", "_") : value

      def text_of(value, key, parent)
        return status_label(value) if key == "label" && parent&.[]("type") == "status"
        return (parent.dig("ref", "id") == value) ? id(value) : data(value) if key == "label" && (parent&.key?("type") || parent&.[]("id") == "current_user")

        text(value)
      end

      # Host-written text stays unless it quotes something that was replaced elsewhere.
      def text(value)
        return fake(value) if @pattern&.match?(value)

        @kept << value unless @learning
        value
      end

      def identifier_id(value, parent)
        (record?(parent) || id_like?(value) || real_id?(value)) ? id(value) : value
      end

      # Menu items and scopes have ids too; a record's sits beside what only a record has.
      def record?(parent)
        return false unless parent

        %w[display_name paths permissions].any? { parent.key?(it) } || (parent.key?("resource") && !parent.key?("kind"))
      end

      def id_like?(value) = value.match?(INTEGER_ID) || value.match?(UUID)

      def vocabulary?(value) = value.is_a?(String) && @scope.include?(value)

      def record_id?(value) = value.is_a?(String) && (real_id?(value) || id_like?(value))

      def choices_of(names) = names.flat_map { [it.to_s, it.to_s.humanize, it.to_s.titleize] }.to_set

      def within(resource)
        was, @resource = @resource, resource&.to_s
        yield
      ensure
        @resource = was
      end

      def with_scope(choices)
        was, @scope = @scope, choices
        yield
      ensure
        @scope = was
      end

      def enum(value) = vocabulary?(value) ? value : data(value)

      # Data under a `value` key: a node's value, a lock, a json blob, a field.
      def data_value(parent, key, value)
        case value
        when Hash then (parent && key == "summary") ? summary(value) : blob(value)
        when Array then (parent && parent["type"] != "json" && value.all? { it.is_a?(Hash) && it.key?("type") }) ? value.map { walk(it, key, parent:) } : value.map { blob(it) }
        when String then (key == "value" && parent&.key?("field")) ? lock(value) : data(value)
        when Integer, Float then number(value)
        else value
        end
      end

      def summary(value)
        value.to_h do |key, item|
          [key, case key
                when "keys" then Array(item).map { data_key(it) }
                when "size" then item
                else walk(item, key)
                end]
        end
      end

      def blob(value)
        case value
        when Hash then value.to_h { |key, item| [data_key(key), blob(item)] }
        when Array then value.map { blob(it) }
        else data_value(nil, nil, value)
        end
      end

      # Every key is faked: a key can name a diagnosis as well as a value can. Injective, so no entry is lost.
      # Learned like a value, so host text quoting a key (a panel titled "Contact jane@doe.test") is scrubbed too.
      def data_key(key)
        @originals << key.to_s unless key.to_s.empty?
        @keys[key.to_s] ||= (0..).lazy.map { slug("#{key}\0#{it}") }.find { @taken_keys.add?(it) }
      end

      def remember(value)
        return unless value.is_a?(String) && !value.empty? && value != ValuePayload::MASK

        @originals << value
        url_pieces(value).each { @originals << it } if value.match?(%r{\A(?:[a-z][a-z0-9+.-]*:)?//|\A/}i)
      end

      # The parts of a url host text might quote on their own: decoded path segments, a file's name without its
      # extension, and query values. Route words and short pieces are left out, since they quote nothing.
      def url_pieces(value)
        rest = value.sub(%r{\A(?:[a-z][a-z0-9+.-]*:)?//[^/?#]*}i, "")
        route, query = rest.split("#", 2).first.to_s.split("?", 2)
        segments = route.to_s.split("/").map { CGI.unescape(it) }.reject { it.size < MIN_LENGTH || @routes.include?(it) }
        stems = segments.filter_map { it.rpartition(".").then { |stem, dot, ext| stem if !dot.empty? && FILE_EXTENSIONS.include?(ext.downcase) } }
        values = query.to_s.split("&").filter_map { CGI.unescape(it.split("=", 2)[1].to_s).presence }.reject { it.size < MIN_LENGTH }
        [*segments, *stems, *values]
      end

      def lock(value)
        time, token = value.split("~", 2)
        [fake(time), (digest("lock", token).unpack1("H#{token.to_s.size.clamp(1, 32)}") if token)].compact.join("~")
      end

      def data(value)
        return value if value.empty? || value == ValuePayload::MASK

        fake(value)
      end

      # Every replacement of a record value goes through here, so the original always feeds quote detection: a
      # replaced value can't then survive where host text quotes it.
      def fake(value)
        remember(value)
        differing(value) { fake_once(value) }
      end

      # Retries with a salted digest until the fake differs from the original ("lorem" can't stay "lorem").
      def differing(original)
        was = @salt
        result = yield
        (1..MAX_SALTS).each do |salt|
          break unless result.to_s == original.to_s

          @salt = salt
          result = yield
        end
        (result.to_s == original.to_s) ? altered(result) : result
      ensure
        @salt = was
      end

      # Past the retries a digest can still land on the original (one digit has nine fakes); one changed character can't.
      def altered(value)
        return value + 1 if value.is_a?(Numeric)

        value = value.to_s
        # Whitespace or punctuation alone is layout, not data.
        index = value.rindex(/[[:alnum:]]/) or return value
        char = value[index]
        value[0...index] + {"9" => "8", "z" => "y", "Z" => "Y"}.fetch(char) { char.match?(/[0-8a-yA-Y]/) ? char.next : "x" } + value[index + 1..]
      end

      def fake_once(value)
        case value
        when UUID then uuid(value)
        when /\A[a-z][a-z0-9+.-]*:\/\//i then "https://example.com/#{slug(value)}"
        when EMAIL then "user#{digits("email", value, 5)}@example.com"
        when TIME then time(value)
        when TIME_OF_DAY then time_of_day(value)
        when NUMBERLIKE then numberlike(value)
        when /<\/?[a-z][^>]*>/i then markup?(value) ? html(value) : words(value)
        else words(value)
        end
      end

      def words(value)
        value.split("\n", -1).first(20).map do |line|
          bytes = digest("words", line).bytes
          line.sub(/\S(?:.*\S)?/) do |text|
            text.split.first(MAX_WORDS).each_with_index.map do |token, index|
              word = WORDS[(bytes[index % bytes.size] + index) % WORDS.size]
              token.match?(/\A\p{Upper}/) ? word.capitalize : word
            end.join(" ")
          end
        end.join("\n")
      end

      # Record text with angle brackets (`Contact <alice@example.test>`) isn't markup: the "element" would be data.
      def markup?(value)
        fragment = HtmlPolicy.parse(value) or return false
        fragment.css("*").any? { HTML_ELEMENTS.include?(it.name) }
      end

      def html(value)
        fragment = HtmlPolicy.parse(value) or return words(value)
        # An element the HTML vocabulary doesn't name is learned and becomes a span, never kept by name.
        fragment.css("*").each do |element|
          next if HTML_ELEMENTS.include?(element.name)

          remember(element.name)
          element.name = "span"
        end
        # Neither text nor elements, so nothing below would scrub them; the client never shows them anyway.
        hidden = []
        fragment.traverse { |node| hidden << node if node.comment? || node.processing_instruction? || node.cdata? }
        hidden.each { discard(it.content) }.each(&:remove)
        fragment.traverse do |node|
          if node.text? then node.content = node.content.sub(/\S.*\S|\S/m) { data(it) }
          elsif node.element?
            limits = input_limits(node)
            node.attribute_nodes.each { |attribute| limits.key?(attribute.name) ? attribute.value = limits[attribute.name] : html_attribute!(node, attribute) }
          end
        end
        fragment.to_html
      end

      def html_attribute!(element, attribute)
        return attribute.value = html_attribute(element, attribute) if @host_markup || HTML_ATTRIBUTES.include?(attribute.name)

        remember(attribute.name)
        remember(attribute.name.sub(/\A(?:data|aria)-/, ""))
        discard(attribute.value)
        attribute.remove
      end

      # What's dropped is never shown, but a label can still quote it: the whole, and its email-, url- and number-like parts.
      def discard(text)
        text = text.to_s.strip
        return if text.empty?

        remember(text)
        text.split(/[\s"'<>(),;]+/).each { remember(it) if it.size >= MIN_LENGTH && it.match?(%r{[@\d:/]}) }
      end

      # A frame's <input> keeps its bounds and value by the rule a typed field follows, so the value stays inside them.
      def input_limits(element)
        return {} unless @host_markup && element.name == "input" && element.key?("min") | element.key?("max")

        html = {"min" => element["min"], "max" => element["max"], "step" => element["step"]}.compact
        node = {"control" => element["type"].to_s.downcase, "name" => element["name"].to_s, "input_html" => html}
        node["value"] = element["value"] if element["value"]
        faked = field(node)
        faked["input_html"].slice("min", "max").merge(faked.slice("value")).transform_values(&:to_s)
      end

      def html_attribute(element, attribute)
        name = attribute.name
        return %w[href src].include?(name) ? path(attribute.value) : data(attribute.value) unless @host_markup
        return attribute.value if name == "name" && FORM_CONTROLS.include?(element.name)
        # Rails masks the CSRF token afresh on every render.
        return "token" if name == "value" && element["name"] == "authenticity_token"
        return attribute.value if name == "value" && element["name"] == "_method" && FORM_METHODS.include?(attribute.value.downcase)
        return attribute.value if %w[method formmethod data-method].include?(name) && FORM_METHODS.include?(attribute.value.downcase)
        # Choices are told apart by value, so they get the injective mapping JSON options get.
        return option_value(attribute.value) if name == "value" && choice_control?(element)
        return attribute.value if %w[enctype formenctype].include?(name) && FORM_ENCODINGS.include?(attribute.value.downcase)
        return path(attribute.value) if %w[action formaction].include?(name)
        return css_classes(attribute.value) if name == "class"
        return css_style(attribute.value) if name == "style"
        # Enumerated values (type="date", role="dialog") name what an element is, so a learned label "Date"
        # mustn't rewrite them; only a value outside a plain enum's shape is treated as data.
        return attribute.value if structural_attribute?(name, attribute.value)
        return path(attribute.value) if %w[href src].include?(name)
        # The client mounts a date picker on exactly this marker, and drops values it doesn't know.
        return attribute.value if name == HtmlPolicy::WIDGET_ATTRIBUTE && HtmlPolicy::WIDGETS.key?(attribute.value)
        return attribute.value.split.map { html_id(it) }.join(" ") if HTML_ID_REFS.include?(name)
        data(attribute.value)
      end

      # A boolean attribute may be empty; any other value has to be a word of the attribute's vocabulary.
      def structural_attribute?(name, value)
        return value.empty? || value.split.all? { ENUM_ATTRIBUTES[name].include?(it) } if ENUM_ATTRIBUTES.key?(name)
        return value.match?(NUMERIC_ATTRIBUTE) if NUMERIC_ATTRIBUTES.include?(name)

        name == "lang" && value.match?(LANGUAGE)
      end

      def choice_control?(element) = element.name == "option" || (element.name == "input" && %w[radio checkbox].include?(element["type"].to_s.downcase))

      # A class or style in html can come from the record, even inside an opaque json value, so only what a closed
      # rule allows is kept: plain class names, and declarations of a plain property with a plain value. A class or
      # value that quotes a scrubbed value is faked, and anything else (custom properties, quotes, urls, @) dropped.
      def css_classes(value)
        value.split.map do |token|
          next token if token.match?(CSS_TOKEN) && !quotes_original?(token)

          remember(token)
          slug(token)
        end.join(" ")
      end

      def css_style(value)
        value.split(";").filter_map do |declaration|
          property, rule = declaration.split(":", 2).map(&:strip)
          next declaration.strip if property&.match?(CSS_PROPERTY) && rule&.match?(CSS_VALUE) && !quotes_original?(rule)

          discard(rule)
          nil
        end.join("; ")
      end

      # One fake per original, never shared, so a label keeps pointing at its own control.
      # An id or a link's fragment can carry record data (`#alice@example.test`), so it's learned like any value.
      def html_id(value)
        remember(value)
        @html_ids[value] ||= (0..).lazy.map { slug("#{value}\0#{it}") }.find { it != value && @taken_html_ids.add?(it) }
      end

      # The client enforces maxlength and minlength, so a faked value that was valid stays valid.
      def fit_length(value, html, original)
        return value unless value.is_a?(String) && html.is_a?(Hash)

        max, min = html.values_at("maxlength", "minlength").map { Integer(it, exception: false) if it.is_a?(Integer) || it.is_a?(String) }
        max = nil unless max&.positive?
        return value if (max.nil? || value.size <= max) && (min.nil? || value.size >= min)

        target = [[value.size, max].compact.min, min].compact.max
        target = max if max && target > max
        # Fitting can land back on the original (u@x.io under a maxlength of 6); then other letters, or filler.
        differing(original) { fitted(value, target) }
      end

      def fitted(value, target)
        local, domain = @salt ? digest("shape", value).bytes.first(2).map { ("a".."z").to_a[it % 26] } : %w[u x]
        case value
        when EMAIL then shaped(value, target, local, "@#{domain}.io", 6)
        when /\A[a-z][a-z0-9+.-]*:\/\//i then shaped(value, target, "https://#{domain}.io/", "", 14)
        else @salt ? digits("fit", value, target) : value.ljust(target, "x")[0, target]
        end
      end

      # A short fake of the same kind (u1@x.io, https://x.io/a) rather than a truncated one that no longer parses.
      def shaped(value, target, prefix, suffix, shortest)
        return (@salt ? digits("fit", value, target) : value[0, target]) if target < shortest

        room = target - prefix.size - suffix.size
        filler = room.positive? ? digits("fit", value, room) : ""
        "#{prefix}#{filler}#{suffix}"
      end

      # A number field whose bounds are kept (small, structural) keeps a valid value valid: faked within them.
      def number_bounds(node)
        html = node["input_html"]
        return unless html.is_a?(Hash) && %w[number range].include?(node["control"])

        bounds = html.values_at("min", "max")
        return if bounds.none? || bounds.compact.any? { !structural_limit?(it) }

        min, max = bounds.map { Float(it) if it }
        step = Float(html["step"], exception: false) if html["step"].is_a?(Numeric) || html["step"].is_a?(String)
        [min, max, step, html["step"].to_s[/\.(\d+)/, 1].to_s.size] if min.nil? || max.nil? || min <= max
      end

      def bounded_number(value, min, max, step, step_decimals)
        number = Float(value, exception: false) if value.is_a?(Numeric) || value.is_a?(String)
        within = number && (min.nil? || number >= min) && (max.nil? || number <= max)
        return field_value(value, Set.new) unless within

        min, max = mirrored(number, min, max)
        remember(value.to_s)
        others, decimals = other_ticks(value, number, min, max, step, step_decimals)
        # Off the grid: an independent fake is all that's left.
        return field_value(value, Set.new) if others.empty?

        fake = others[digest("bounded", value.to_s).unpack1("N") % others.size].round(decimals)
        return fake.to_i if value.is_a?(Integer)
        return (decimals.zero? ? fake.to_i.to_s : format("%.#{decimals}f", fake)) if value.is_a?(String)

        fake
      end

      def other_ticks(value, number, min, max, step, step_decimals)
        whole = value.is_a?(Integer) || (value.is_a?(String) && !value.include?("."))
        step = nil unless step&.positive?
        decimals = 0
        decimals = [(step ? step_decimals : 0), value.to_s[/\.(\d+)/, 1].to_s.size].max unless whole
        [grid(min, max, step || 10.0**-decimals, whole).reject { (it - number).abs < 1e-9 }, decimals]
      end

      # Kept bounds that admit only the original (min = max = 3) reveal it, so they move with it instead.
      def pinned?(node)
        min, max, step, step_decimals = number_bounds(node)
        value = node["value"]
        return false if (min.nil? && max.nil?) || !numeric?(value)

        number = Float(value)
        return false if (min && number < min) || (max && number > max)

        other_ticks(value, number, *mirrored(number, min, max), step, step_decimals).first.empty?
      end

      # With one bound declared, the open side mirrors the value's distance from it, so the fake stays as plausible.
      def mirrored(number, min, max)
        min ||= (number >= 0) ? [0.0, 2 * number - max].max : 2 * number - max
        [min, max || 2 * number - min + 1]
      end

      # The step's ticks from min, as exact rationals so 0.3 * 26 is 7.8; whole values keep only whole ticks.
      def grid(min, max, step, whole)
        start, unit = Rational(min.to_s), Rational(step.to_s)
        count = ((Rational(max.to_s) - start) / unit).floor
        ticks = (0..[count, MAX_TICKS].min).map { start + it * unit }
        ticks = ticks.select { it.denominator == 1 } if whole
        ticks.map(&:to_f)
      end

      # A field whose bounds can't be kept (2.5, 25000, any date) gets fake bounds of its own, in order, and a value
      # drawn anywhere on the grid inside them. Nothing ties the fake value to a real bound, so knowing a bound (a
      # hard-coded 1900-01-01) doesn't give the value back.
      def interval(node)
        html = node["input_html"]
        return unless html.is_a?(Hash)

        limits = html.values_at("min", "max")
        axis = if %w[number range].include?(node["control"]) && limits.any? { numeric?(it) }
          NumberAxis.for(html, node["value"]) unless number_bounds(node) && !pinned?(node)
        elsif limits.any? { it.is_a?(String) && it.match?(TIME) }
          TimeAxis.for(html, node["value"])
        end
        axis && fake_interval(node["param"] || node["name"], {"min" => html["min"], "max" => html["max"], "value" => node["value"]}, axis)
      end

      def fake_interval(key, raw, axis)
        originals = raw.transform_values { axis.at(it) }.compact
        return if originals.empty?

        raw.slice(*originals.keys).each_value { remember(it.to_s) }
        fakes = nil
        (0..5).each do |salt|
          fakes = draw(key, salt, *originals.values_at("min", "max", "value"), axis).compact
          break if fakes.none? { |name, at| at == originals[name] }
        end
        fakes.to_h { |name, at| [name, axis.format(raw[name], at)] }
      end

      def draw(key, salt, min, max, value, axis)
        pick = ->(kind, choices) { digest(kind, "#{key}\0#{salt}").unpack1("Q>") % choices }
        unit, steps = axis.unit, (axis.span / axis.unit).floor
        anchor = axis.base + unit * pick.call("anchor", steps + 1)
        width = (min == max) ? 0 : unit * (1 + pick.call("width", ((max - min) * 2 / unit).floor.clamp(1, steps))) if min && max
        low = anchor if min
        high = min ? anchor + width : anchor if max
        return {"min" => low, "max" => high} unless value

        from = low || [high - axis.span, axis.base].max
        to = high || from + axis.span
        {"min" => low, "max" => high, "value" => from + unit * pick.call("value", ((to - from) / unit).floor + 1)}
      end

      def with_interval(fakes)
        was, @interval = @interval, fakes
        yield
      ensure
        @interval = was
      end

      def numeric?(value) = Scrubber.numeric?(value)

      def time(value)
        _, _, separator, clock, fraction, zone = *TIME.match(value)
        base = Time.utc(2020, 1, 1) + digest("time", value).unpack1("N") % (5 * 365 * 86_400)
        return base.strftime("%F") unless clock

        "#{base.strftime("%F")}#{separator}#{clock_of(base, clock)}#{fraction&.then { "." + "0" * (it.size - 1) }}#{zone}"
      end

      # A datetime-local value can stop at minutes (12:30); the fake keeps the same precision.
      def clock_of(time, clock) = time.strftime((clock.count(":") == 1) ? "%H:%M" : "%T")

      def time_of_day(value)
        hour, minute, second = digest("clock", value).unpack("CCC").zip([24, 60, 60]).map { |byte, limit| byte % limit }
        clock = (value.count(":") == 2) ? format("%02d:%02d:%02d", hour, minute, second) : format("%02d:%02d", hour, minute)
        (fraction = value[/\.\d+\z/]) ? "#{clock}.#{"0" * (fraction.size - 1)}" : clock
      end

      def numberlike(value)
        seen = 0
        value.gsub(/\d/) do |digit|
          seen += 1
          fresh = digest("number", "#{value}#{seen}").bytes.first % 10
          if seen == 1 && digit != "0"
            (fresh.zero? ? 1 : fresh).to_s
          else
            fresh.to_s
          end
        end
      end

      def number(value)
        return value if value.zero?

        @originals << value.to_s
        differing(value) { number_once(value) }
      end

      def number_once(value)
        mantissa, exponent = value.abs.to_s.split("e", 2)
        whole, fraction = mantissa.split(".", 2)
        fake = numberlike(whole)
        fake = "#{fake}.#{numberlike("1#{fraction}")[1..]}" if fraction
        fake = "#{fake}e#{exponent}" if exponent
        faked = value.is_a?(Float) ? Float(fake) : Integer(fake)
        (value.negative? ? -1 : 1) * (faked.infinite? ? 1.0 : faked)
      end

      def uuid(value)
        hex = digest("uuid", value).unpack1("H32")
        [hex[0, 8], hex[8, 4], "4#{hex[13, 3]}", "a#{hex[17, 3]}", hex[20, 12]].join("-")
      end

      def slug(value) = "#{WORDS[digest("slug", value).bytes.first % WORDS.size]}-#{digits("slug", value, 4)}"

      def digits(kind, value, length) = digest(kind, value).unpack1("N").to_s.rjust(length, "0")[-length..]

      def digest(kind, value) = Digest::SHA256.digest("#{@seed}#{"\0#{@salt}" if @salt}\0#{kind}\0#{value}")

      # Injective: two records never share a fake id, whatever the digest says.
      # The learning pass only collects the real ids; mapping waits for the scrub pass, so a fake is never a real
      # id, its own or another record's.
      def id(value)
        @originals << value
        return @real_ids.add(value) && value if @learning

        @ids[value] ||= (0..).lazy.map { fake_id(value, it) }.find { !@real_ids.include?(it) && @taken.add?(it) }
      end

      def real_id?(value) = @real_ids.include?(value)

      # An Integer id gets the mapping of its string form and stays an Integer.
      def integer_id(value) = id(value.to_s).then { it.match?(INTEGER_ID) ? it.to_i : it }

      def fake_id(value, attempt)
        seed = "#{value}#{attempt}"
        return uuid(seed) if value.match?(UUID)
        # One more digit every so many collisions, so a crowded space (ids 1..9999) still yields a fresh fake.
        if value.match?(INTEGER_ID)
          sign, number = value.start_with?("-") ? ["-", value[1..]] : ["", value]
          return "#{sign}#{1 + digest("id", seed).unpack1("N") % 9}#{digits("id", seed, [number.size, MIN_LENGTH].max - 1 + attempt / ID_RETRIES)}"
        end

        slug(seed)
      end

      def path(value)
        return value if value.empty?
        return contact(value, "mailto:user@example.com") if value.start_with?("mailto:")
        return contact(value, "tel:0000000000") if value.start_with?("tel:")
        return "data:," if value.start_with?("data:")
        return fake(value) if value.match?(%r{\A([a-z][a-z0-9+.-]*:)?//}i)

        before_fragment, fragment = value.split("#", 2)
        route, query = before_fragment.split("?", 2)
        route = route.to_s.split("/", -1).map { segment(it) }.join("/")
        [route, (query.split("&", -1).map { parameter(it) }.join("&") if query)].compact.join("?") + (fragment ? "##{html_id(CGI.unescape(fragment)) unless fragment.empty?}" : "")
      end

      # The address or number, and any query values (a subject, a body), are learned before the constant stands in.
      def contact(value, replacement)
        target, query = value.split(":", 2).last.to_s.split("?", 2)
        # In the address or number a + is literal (+15550123456); only query values are form-encoded.
        [decode_target(target.to_s), *query.to_s.split("&").map { CGI.unescape(it.split("=", 2)[1].to_s) }].each { remember(it) }
        replacement
      end

      # Malformed escapes are learned as written rather than stopping the recording.
      def decode_target(target)
        URI.decode_uri_component(target)
      rescue ArgumentError
        target
      end

      def segment(value)
        plain = CGI.unescape(value)
        return ERB::Util.url_encode(id(plain)) if real_id?(plain) || id_like?(plain)
        return value if plain.empty? || PLACEHOLDERS.include?(plain) || %w[. ..].include?(plain) || @routes.include?(plain)

        remember(plain)
        stem, dot, extension = plain.rpartition(".")
        return slug(plain) if dot.empty? || !FILE_EXTENSIONS.include?(extension.downcase)

        remember(stem)
        "#{slug(stem)}.#{extension.downcase}"
      end

      def parameter(pair)
        return pair if pair.empty?

        name, value = pair.split("=", 2)
        key, plain = CGI.unescape(name), CGI.unescape(value.to_s)
        unless structural_name?(key)
          fake = query_name(key)
          return value ? "#{fake}=#{CGI.escape(data(plain)) unless plain.empty?}" : fake
        end
        return pair if plain.empty? || structural_query?(key, plain)
        return "#{name}=#{ERB::Util.url_encode(id(plain))}" if key == "id"

        # A minted token differs on every run; its fake must not.
        remember(plain) if name == "token"
        "#{name}=#{(name == "token") ? "token" : CGI.escape(data(plain))}"
      end

      def structural_name?(key) = QUERY_NAMES.include?(key[QUERY_NAME, :base])

      def query_name(key)
        remember(key)
        CGI.escape(slug(key))
      end

      def structural_query?(key, value)
        return value.match?(DIGITS) if NUMERIC_QUERY_KEYS.include?(key)
        return QUERY_CONTEXTS.include?(value) if key == "context"

        @known[key].include?(value)
      end

      # A number field's interval as rationals on its step (or its finest decimal), around zero at the bounds' size.
      NumberAxis = Struct.new(:unit, :base, :span, :decimals) do
        def self.for(html, value)
          step = html["step"] if html["step"].is_a?(Numeric) || html["step"].to_s.match?(/\A\d+(?:\.\d+)?\z/)
          numbers = [html["min"], html["max"], value].select { Scrubber.numeric?(it) }
          decimals = [*numbers, step].compact.map { it.to_s[/\.(\d+)/, 1].to_s.size }.max
          unit = (step && Rational(step.to_s).positive?) ? Rational(step.to_s) : Rational(1, 10**decimals)
          size = ([*numbers.map { Rational(it.to_s).abs }, 1].max / unit).ceil * unit
          negative = numbers.any? { Rational(it.to_s).negative? }
          new(unit, negative ? -size : 0, negative ? 2 * size : size, decimals)
        end

        def at(value) = (Rational(value.to_s) if Scrubber.numeric?(value))

        def format(original, at)
          return at.to_i if original.is_a?(Integer) && at.denominator == 1
          return (decimals.zero? ? at.to_i.to_s : Kernel.format("%.#{decimals}f", at)) if original.is_a?(String)

          at.to_f.round(decimals)
        end
      end

      # A date or datetime field's interval in seconds: whole days for dates, minutes for a clock without seconds.
      TimeAxis = Struct.new(:unit, :base, :span) do
        def self.for(html, value)
          times = [html["min"], html["max"], value].grep(String).filter_map { TIME.match(it) }
          clocks = times.filter_map { it[3] }
          unit = if clocks.size < times.size then 86_400
          elsif clocks.all? { it.count(":") == 1 } then 60
          else 1
          end
          new(unit, Time.utc(2000).to_i, 25 * 365 * 86_400)
        end

        def at(value)
          _, date, _, clock = *TIME.match(value.to_s)
          Time.utc(*date.split("-").map(&:to_i), *clock.to_s.split(":").map(&:to_i)).to_i if date
        rescue ArgumentError
          nil
        end

        def format(original, at)
          _, _, separator, clock, fraction, zone = *TIME.match(original)
          time = Time.at(at).utc
          return time.strftime("%F") unless clock

          "#{time.strftime("%F")}#{separator}#{time.strftime((clock.count(":") == 1) ? "%H:%M" : "%T")}#{fraction&.then { "." + "0" * (it.size - 1) }}#{zone}"
        end
      end
    end
  end
end
