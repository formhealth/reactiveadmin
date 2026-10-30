class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  def self.ransackable_attributes(_auth = nil) = column_names + _ransackers.keys

  def self.ransackable_associations(_auth = nil) = reflect_on_all_associations.map { it.name.to_s }

  def self.ransackable_scopes(_auth = nil) = []
end
