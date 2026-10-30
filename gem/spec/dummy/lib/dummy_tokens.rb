# Stands in for a host's token store.
module DummyTokens
  STORE = {}

  def self.issue(user, scopes: nil, client_id: nil)
    "tok_#{SecureRandom.hex(8)}".tap { STORE[it] = {user_id: user.id, scopes:, client_id:} }
  end

  def self.resolve(token)
    entry = STORE[token] or return
    user = AdminUser.find_by(id: entry[:user_id]) or return
    (entry[:scopes] || entry[:client_id]) ? {user:, scopes: entry[:scopes], client_id: entry[:client_id]} : user
  end
end
