module Crumble::Cookie::Consent
  def self.locale_for(ctx)
    locale = if accept_language = ctx.request.headers["Accept-Language"]?
               HTTP::Accept::Language.best_locale(Crababel.locales, HTTP::Accept::Language.parse(accept_language), "en")
             else
               "en"
             end
    Crababel.locale(locale)
  end

  css_class Banner

  style do
    layer :crumble_cookie_consent do
      rule Banner do
        position :fixed
        left 0
        right 0
        bottom 0
        display :flex
        align_items :center
        justify_content :space_between
        gap 1.rem
        box_sizing :border_box
        padding 0.75.rem, 1.rem
        background_color :white
        color "#111827"
        box_shadow 0.px, -0.125.rem, 0.5.rem, rgb(0, 0, 0, alpha: 15.percent)
        z_index 2147483640
      end
    end
  end

  class Action < ::Crumble::Turbo::Action
    controller do
      ctx.session.update!(__crumble_cookie_consented: true)
      ctx.refresh_session_cookie
    end

    policy do
      can_view do
        !ctx.cookie_consented?
      end
    end

    view do
      template do
        translations = Crumble::Cookie::Consent.locale_for(ctx).crumble.cookie.consent.action.template
        aside Banner, role: "dialog", aria: {label: translations.label} do
          p { translations.message }

          action_form.to_html do
            button { translations.accept }
          end
        end
      end
    end
  end
end
