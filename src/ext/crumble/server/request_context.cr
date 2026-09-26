class Crumble::Server::RequestContext
  def cookie_consented? : Bool
    return false unless stored_session?

    session.__crumble_cookie_consented || false
  end

  def cookie_consent_chosen? : Bool
    return false unless stored_session?

    !session.__crumble_cookie_consented.nil?
  end

  # Requiring this shard makes every newly issued session ID browser-scoped,
  # regardless of an application's configured post-consent lifetime.
  def new_session_cookie_max_age
    nil
  end
end
