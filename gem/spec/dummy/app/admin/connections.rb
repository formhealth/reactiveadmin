ActiveAdmin.register_page "Connections" do
  menu false

  content do
    para { button_to "Connect with Provider", "/auth/provider", params: {origin: "/admin/connections"} }
    para { button_to "Connect on this host", "http://www.example.com/auth/absolute", data: {confirm: "Link your account?"} }
    para { link_to "Connect by link", "/auth/link?x=1", method: :post }
    para { button_to "Connect elsewhere", "https://evil.example/auth/provider" }
    para { button_to "Connect through a dot segment", "/auth/../admin/posts" }
    para { button_to "Connect to the API", "/api/admin/_session" }
    para { button_to "Connect by script", "javascript:alert(1)" }
    para { link_to "Open provider page", "/auth/provider" }
    div { raw %(<form method="post" action="/auth/stored"><button type="submit">Stored connect</button></form>) }
    render partial: "admin/connections/forms"
  end
end
