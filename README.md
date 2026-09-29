# crumble-cookie-consent

Cookie-consent support for [Crumble](https://github.com/sbsoftware/crumble).

Requiring this shard keeps Crumble's essential session cookie scoped to the
current browser session until the user makes a choice. After consent, the same
cookie is reissued with the lifetime configured by the application. Applications
can use `ctx.cookie_consented?` to guard optional cookie-dependent features and
`ctx.cookie_consent_chosen?` to distinguish denial from no choice yet.

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  crumble-cookie-consent:
    github: sbsoftware/crumble-cookie-consent
```

Then run `shards install` and require the shard from your application:

```crystal
require "crumble-cookie-consent"
```

## Usage

Render the fixed consent banner in the application layout:

```crystal
ToHtml.class_template do
  html do
    body do
      yield
      Crumble::Cookie::Consent::Banner.new(ctx).to_html
    end
  end
end
```

The banner submits through `crumble-turbo`, records acceptance or denial in the
session, and removes itself after a successful submission. The typed CSS class
`Crumble::Cookie::Consent::Banner` is applied to its outer element for
application styling. A default banner style is added to the layout automatically
inside the `crumble-cookie-consent` cascade layer. Normal, unlayered application
rules targeting `Crumble::Cookie::Consent::Banner` take precedence over these
defaults without requiring additional selector specificity.

Configure the post-consent lifetime through Crumble's existing request-context
method:

```crystal
class Crumble::Server::RequestContext
  def session_cookie_max_age
    365.days
  end
end
```

Without consent, this configured value is intentionally ignored and new session
cookies have no `Max-Age`. If the method returns `nil`, the cookie remains scoped
to the browser session after consent as well.

Guard optional behavior wherever a request context is available:

```crystal
if ctx.cookie_consented?
  enable_optional_cookie_feature
else
  show_cookie_consent_hint
end
```

The shard does not block application behavior automatically. It remains the
application's responsibility to guard any feature that requires consent.

## Development

```shell
shards install
crystal tool format --check src spec
crystal spec
```

## Contributing

1. Fork the repository.
2. Create a feature branch.
3. Add focused specs for the changed behavior.
4. Run formatting and the full spec suite.
5. Open a pull request.

## Contributors

- [Stefan Bilharz](https://github.com/sbsoftware) — creator and maintainer
