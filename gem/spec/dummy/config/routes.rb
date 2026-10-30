Rails.application.routes.draw do
  get "/login", to: "test_sessions#new"
  delete "/logout", to: "test_sessions#destroy"
  post "/test/sign_in", to: "test_sessions#create"

  ActiveAdmin.routes(self)
  ReactiveAdmin.routes(self)
end
