module ReactiveAdmin
  module AA
    # ActiveAdmin 3.5 (activeadmin >= 3.5, < 4). The public methods are the adapter contract;
    # `AA::V4` inherits them and lists what has to change.
    module V3
      require "reactive_admin/aa/v3/registry"
      require "reactive_admin/aa/v3/controller"
      require "reactive_admin/aa/v3/install"
      require "reactive_admin/aa/v3/presenters"
      require "reactive_admin/aa/v3/views"
      require "reactive_admin/aa/v3/menu"
      require "reactive_admin/aa/v3/forms"

      include Registry
      include Controller
      include Install
      include Presenters
      include Views
      include Menu
      include Forms
    end
  end
end
