module Crumble::Cookie::Consent
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
    form do
      field consent : Bool
    end

    controller do
      ctx.session.update!(__crumble_cookie_consented: form.consent)
      ctx.refresh_session_cookie if form.consent
    end

    policy do
      can_view do
        !ctx.cookie_consent_chosen?
      end
    end

    view do
      template do
        aside Banner, role: "dialog", aria: {label: t.label} do
          p { t.message }

          action_form.to_html do
            button name: "consent", value: "true" do
              t.accept
            end
            button name: "consent", value: "false" do
              "Deny cookies"
            end
          end
        end
      end
    end
  end
end
