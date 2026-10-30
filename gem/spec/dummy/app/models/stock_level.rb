class StockLevel < ApplicationRecord
  self.primary_key = [:warehouse, :sku]
end
