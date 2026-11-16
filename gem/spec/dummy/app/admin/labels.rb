# A PORO decorator, the kind `decorate_with` accepts without Draper.
class LabelDecorator < SimpleDelegator
  def decorated? = true

  def model = __getobj__

  def shout = "#{name.upcase}!"
end

ActiveAdmin.register Tag, as: "Label" do
  menu false

  decorate_with LabelDecorator
  permit_params :name

  filter :name

  index do
    column :name
    column(:shout) { |label| label.shout }
    actions
  end

  show do
    attributes_table do
      row :name
      row(:shout) { |label| label.shout }
    end
  end

  form do |f|
    f.inputs { f.input :name }
  end
end
