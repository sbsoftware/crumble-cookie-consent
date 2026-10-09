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
      ctx.cookie_consent_chosen?.should be_false
      store.has_key?(ctx.session_id).should be_false
    end
  end

  describe Crumble::Cookie::Consent::BannerView do
    it "provides and negotiates every supported locale" do
      expected_labels = {
        "en" => "Cookie consent", "de" => "Cookie-Einwilligung", "es" => "Consentimiento de cookies", "fr" => "Consentement aux cookies",
        "pt" => "Consentimento de cookies", "tr" => "Çerez izni", "pl" => "Zgoda na pliki cookie", "cs" => "Souhlas se soubory cookie",
        "it" => "Consenso ai cookie", "ru" => "Согласие на использование файлов cookie", "nl" => "Cookietoestemming", "ja" => "Cookieの使用に関する同意",
        "zh" => "Cookie 使用许可", "ar" => "الموافقة على ملفات تعريف الارتباط", "ko" => "쿠키 사용 동의", "vi" => "Chấp thuận cookie",
      }

      Crababel.locales.should eq(expected_labels.keys.sort)
      expected_labels.each do |locale, label|
        headers = HTTP::Headers{"Accept-Language" => locale}
        ctx = ConfiguredCookieRequestContext.new(headers: headers)

        Crumble::Crababel.locale_for(ctx).should eq(Crababel.locale(locale))
        Crumble::Cookie::Consent::BannerView.new(ctx).to_html.should contain(%(aria-label="#{label}"))
      end
    end

    it "negotiates regional language tags to their base translations" do
      {"pt-BR" => "pt", "zh-Hans-CN" => "zh", "de-DE" => "de"}.each do |language, locale|
        headers = HTTP::Headers{"Accept-Language" => language}
        ctx = ConfiguredCookieRequestContext.new(headers: headers)

        Crumble::Crababel.locale_for(ctx).should eq(Crababel.locale(locale))
      end
    end

    it "renders the fixed consent banner in English before consent" do
      ctx = ConfiguredCookieRequestContext.new
      html = Crumble::Cookie::Consent::BannerView.new(ctx).to_html

      html.should contain(%(class="#{Crumble::Cookie::Consent::Banner}"))
      html.should contain(%(id="#{Crumble::Cookie::Consent::BannerView::Id}"))
      html.should contain(%(aria-label="Cookie consent"))
      html.should contain("This site uses cookies to provide optional features and remember your session.")
      html.should contain("Accept cookies")
      html.should contain("Deny cookies")
      html.should contain(%(action="#{Crumble::Cookie::Consent::AcceptAction.uri_path}"))
      html.should contain(%(action="#{Crumble::Cookie::Consent::DenyAction.uri_path}"))
      html.should_not contain(%(name="consent"))
    end

    it "renders the fixed consent banner in German" do
      headers = HTTP::Headers{"Accept-Language" => "de-DE,de;q=0.9,en;q=0.8"}
      ctx = ConfiguredCookieRequestContext.new(headers: headers)
      html = Crumble::Cookie::Consent::BannerView.new(ctx).to_html

      html.should contain(%(aria-label="Cookie-Einwilligung"))
      html.should contain("Diese Website verwendet Cookies, um optionale Funktionen bereitzustellen und deine Sitzung zu speichern.")
      html.should contain("Cookies akzeptieren")
      html.should contain("Cookies ablehnen")
    end

    it "does not render the banner after consent" do
      store = Crumble::Server::MemorySessionStore.new
      session = Crumble::Server::Session.new
      session.__crumble_cookie_consented = true
      store.set(session)
      headers = request_headers_with_session(session.id)
      ctx = ConfiguredCookieRequestContext.new(headers: headers, session_store: store)

      Crumble::Cookie::Consent::BannerView.new(ctx).to_html.should be_empty
      ctx.cookie_consented?.should be_true
      ctx.cookie_consent_chosen?.should be_true
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
        resource: Crumble::Cookie::Consent::AcceptAction.uri_path,
        headers: headers,
        body: "consent=false",
        session_store: store,
      )
      post_ctx.request.headers["Content-Type"] = "application/x-www-form-urlencoded"

      Crumble::Cookie::Consent::AcceptAction.handle(post_ctx).should be_true
      promoted_cookie = post_ctx.response.cookies[Crumble::Server::RequestContext::SESSION_COOKIE_NAME]

      store[session_id].__crumble_cookie_consented.should be_true
      promoted_cookie.value.should eq(session_id.to_s)
      promoted_cookie.max_age.should eq(30.days)
      promoted_cookie.http_only.should be_false
      promoted_cookie.samesite.should eq(HTTP::Cookie::SameSite::Strict)
      promoted_cookie.secure.should be_true

      post_ctx.response.flush
      response_body.to_s.should contain(%(<turbo-stream action="replace"))
      response_body.to_s.should contain(%(targets="##{Crumble::Cookie::Consent::BannerView::Id}"))
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
        resource: Crumble::Cookie::Consent::AcceptAction.uri_path,
        headers: headers,
        session_store: store,
      )
      post_ctx.request.headers["Content-Type"] = "application/x-www-form-urlencoded"

      Crumble::Cookie::Consent::AcceptAction.handle(post_ctx).should be_true

      post_ctx.response.cookies[Crumble::Server::RequestContext::SESSION_COOKIE_NAME].max_age.should be_nil
    end

    it "persists denial and hides the banner" do
      store = Crumble::Server::MemorySessionStore.new
      initial_ctx = ConfiguredCookieRequestContext.new(session_store: store)
      session_id = Crumble::Server::SessionKey.new(UUID.new(initial_ctx.response.cookies[Crumble::Server::RequestContext::SESSION_COOKIE_NAME].value))
      headers = request_headers_with_session(session_id)
      response_body = IO::Memory.new
      post_ctx = ConfiguredCookieRequestContext.new(response_io: response_body, method: "POST", resource: Crumble::Cookie::Consent::DenyAction.uri_path, headers: headers, body: "consent=true", session_store: store)
      post_ctx.request.headers["Content-Type"] = "application/x-www-form-urlencoded"

      Crumble::Cookie::Consent::DenyAction.handle(post_ctx).should be_true

      store[session_id].__crumble_cookie_consented.should be_false
      post_ctx.cookie_consented?.should be_false
      post_ctx.cookie_consent_chosen?.should be_true
      post_ctx.response.cookies[Crumble::Server::RequestContext::SESSION_COOKIE_NAME]?.should be_nil
      Crumble::Cookie::Consent::BannerView.new(post_ctx).to_html.should be_empty
      post_ctx.response.flush
      response_body.to_s.should contain(%(targets="##{Crumble::Cookie::Consent::BannerView::Id}"))
      response_body.to_s.should contain("<template></template>")
    end

    it "rejects a repeated choice" do
      store = Crumble::Server::MemorySessionStore.new
      session = Crumble::Server::Session.new
      session.__crumble_cookie_consented = false
      store.set(session)
      headers = request_headers_with_session(session.id)
      ctx = ConfiguredCookieRequestContext.new(method: "POST", resource: Crumble::Cookie::Consent::AcceptAction.uri_path, headers: headers, session_store: store)

      Crumble::Cookie::Consent::AcceptAction.handle(ctx).should be_true

      ctx.response.status_code.should eq(403)
      store[session.id].__crumble_cookie_consented.should be_false
      ctx.response.cookies[Crumble::Server::RequestContext::SESSION_COOKIE_NAME]?.should be_nil
    end
  end

  describe "action templates" do
    it "provides empty templates for form-only consent actions" do
      ctx = ConfiguredCookieRequestContext.new

      Crumble::Cookie::Consent::AcceptAction.new(ctx).action_template.to_html.should eq(%(<div id="#{Crumble::Cookie::Consent::AcceptAction::Template::Id}"></div>))
      Crumble::Cookie::Consent::DenyAction.new(ctx).action_template.to_html.should eq(%(<div id="#{Crumble::Cookie::Consent::DenyAction::Template::Id}"></div>))
    end
  end

  it "serializes the consent state with the session" do
    session = Crumble::Server::Session.new
    session.__crumble_cookie_consented = true

    restored = Crumble::Server::Session.from_yaml(session.to_yaml)

    restored.__crumble_cookie_consented.should be_true
  end

  it "serializes denied consent separately from no choice" do
    denied = Crumble::Server::Session.new
    denied.__crumble_cookie_consented = false

    Crumble::Server::Session.from_yaml(denied.to_yaml).__crumble_cookie_consented.should be_false
    Crumble::Server::Session.from_yaml(Crumble::Server::Session.new.to_yaml).__crumble_cookie_consented.should be_nil
  end
end
