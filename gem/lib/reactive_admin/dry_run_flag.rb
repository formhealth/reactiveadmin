module ReactiveAdmin
  # The API's `dry_run` flag, taken out of params so AA never sees it. Only an update can honor it; on
  # any other action (a GET custom action and a page action included) ignoring it would run the action
  # for real, so it is refused.
  module DryRunFlag
    private

    def reactiveadmin_dry_run? = @reactiveadmin_dry_run == true

    def take_dry_run_param = (@reactiveadmin_dry_run = ActiveModel::Type::Boolean.new.cast(params.delete(:dry_run)) == true)

    def dry_run_supported? = false

    def refuse_unsupported_dry_run
      raise ApiErrors::BadRequest, "dry_run is only supported for update" if reactiveadmin_request? && reactiveadmin_dry_run? && !dry_run_supported?
    end
  end
end
