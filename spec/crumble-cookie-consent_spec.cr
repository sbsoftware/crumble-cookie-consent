require "./spec_helper"

private class ConfiguredCookieRequestContext < Crumble::Server::TestRequestContext
  def session_cookie_max_age
    30.days
  end

  def session_cookie_http_only
    false
  end

  def session_cookie_same_site
    :strict
  end

  def session_cookie_secure
    true
  end
end

private def request_headers_with_session(session_id)
  headers = HTTP::Headers.new
  cookies = HTTP::Cookies.new
  cookies[Crumble::Server::RequestContext::SESSION_COOKIE_NAME] = session_id.to_s
  cookies.add_request_headers(headers)
  headers
end

describe Crumble::Cookie::Consent do
  describe Crumble::Server::RequestContext do
    it "creates a browser-session cookie even when a persistent lifetime is configured" do
      ctx = ConfiguredCookieRequestContext.new
      cookie = ctx.response.cookies[Crumble::Server::RequestContext::SESSION_COOKIE_NAME]

      cookie.max_age.should be_nil
      cookie.http_only.should be_false
      cookie.samesite.should eq(HTTP::Cookie::SameSite::Strict)
      cookie.secure.should be_true
    end

    it "replaces an invalid cookie with a browser-session cookie" do
      headers = request_headers_with_session("not-a-session-id")
      ctx = ConfiguredCookieRequestContext.new(headers: headers)
      cookie = ctx.response.cookies[Crumble::Server::RequestContext::SESSION_COOKIE_NAME]

      cookie.value.should_not eq("not-a-session-id")
      cookie.max_age.should be_nil
    end

    it "reports no consent without creating a stored session" do
      store = Crumble::Server::MemorySessionStore.new
      ctx = ConfiguredCookieRequestContext.new(session_store: store)

      ctx.cookie_consented?.should be_false
      store.has_key?(ctx.session_id).should be_false
    end
  end

  describe Crumble::Cookie::Consent::Action do
    it "renders the fixed consent banner before consent" do
      ctx = ConfiguredCookieRequestContext.new
      html = Crumble::Cookie::Consent::Action.new(ctx).action_template.to_html

      html.should contain(%(class="#{Crumble::Cookie::Consent::Banner}"))
      html.should contain("This site uses cookies to provide optional features and remember your session.")
      html.should contain("Accept cookies")
      html.should contain(%(action="#{Crumble::Cookie::Consent::Action.uri_path}"))
    end

    it "does not render the banner after consent" do
      store = Crumble::Server::MemorySessionStore.new
      session = Crumble::Server::Session.new
      session.__crumble_cookie_consented = true
      store.set(session)
      headers = request_headers_with_session(session.id)
      ctx = ConfiguredCookieRequestContext.new(headers: headers, session_store: store)

      Crumble::Cookie::Consent::Action.new(ctx).action_template.to_html.should be_empty
      ctx.cookie_consented?.should be_true
    end

    it "persists consent and promotes the existing cookie" do
      store = Crumble::Server::MemorySessionStore.new
      initial_ctx = ConfiguredCookieRequestContext.new(session_store: store)
      initial_cookie = initial_ctx.response.cookies[Crumble::Server::RequestContext::SESSION_COOKIE_NAME]
      session_id = Crumble::Server::SessionKey.new(UUID.new(initial_cookie.value))
      headers = request_headers_with_session(session_id)

      response_body = IO::Memory.new
      post_ctx = ConfiguredCookieRequestContext.new(
        response_io: response_body,
        method: "POST",
        resource: Crumble::Cookie::Consent::Action.uri_path,
        headers: headers,
        session_store: store,
      )

      Crumble::Cookie::Consent::Action.handle(post_ctx).should be_true
      promoted_cookie = post_ctx.response.cookies[Crumble::Server::RequestContext::SESSION_COOKIE_NAME]

      store[session_id].__crumble_cookie_consented.should be_true
      promoted_cookie.value.should eq(session_id.to_s)
      promoted_cookie.max_age.should eq(30.days)
      promoted_cookie.http_only.should be_false
      promoted_cookie.samesite.should eq(HTTP::Cookie::SameSite::Strict)
      promoted_cookie.secure.should be_true

      post_ctx.response.flush
      response_body.to_s.should contain(%(<turbo-stream action="replace"))
      response_body.to_s.should contain("<template></template>")
    end

    it "keeps the promoted cookie browser-scoped when no lifetime is configured" do
      store = Crumble::Server::MemorySessionStore.new
      initial_ctx = Crumble::Server::TestRequestContext.new(session_store: store)
      initial_cookie = initial_ctx.response.cookies[Crumble::Server::RequestContext::SESSION_COOKIE_NAME]
      session_id = Crumble::Server::SessionKey.new(UUID.new(initial_cookie.value))
      headers = request_headers_with_session(session_id)
      post_ctx = Crumble::Server::TestRequestContext.new(
        method: "POST",
        resource: Crumble::Cookie::Consent::Action.uri_path,
        headers: headers,
        session_store: store,
      )

      Crumble::Cookie::Consent::Action.handle(post_ctx).should be_true

      post_ctx.response.cookies[Crumble::Server::RequestContext::SESSION_COOKIE_NAME].max_age.should be_nil
    end
  end

  it "serializes the consent state with the session" do
    session = Crumble::Server::Session.new
    session.__crumble_cookie_consented = true

    restored = Crumble::Server::Session.from_yaml(session.to_yaml)

    restored.__crumble_cookie_consented.should be_true
  end
end
