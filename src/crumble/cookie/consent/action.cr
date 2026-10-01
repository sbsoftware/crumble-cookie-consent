module Crumble::Cookie::Consent
  class Banner
    include ::Crumble::Crababel

    css_class Container

    getter ctx : ::Crumble::Server::RequestContext | ::Crumble::Server::HandlerContext

    def initialize(@ctx : ::Crumble::Server::RequestContext | ::Crumble::Server::HandlerContext); end

    class Id < CSS::ElementId; end

    def dom_id
      Id
    end

    def turbo_stream
      TurboStream(Banner).new(:replace, dom_id.to_css_selector, self)
    end

    ToHtml.instance_template do
      unless ctx.cookie_consent_chosen?
        aside dom_id, Container, role: "dialog", aria: {label: t.label} do
          p { t.message }

          AcceptAction.new(ctx).action_form.to_html do
            button { t.accept }
          end
          DenyAction.new(ctx).action_form.to_html do
            button { t.deny }
          end
        end
      end
    end

    include IdentifiableView

    style do
      layer :crumble_cookie_consent do
        rule Container do
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
  end

  abstract class Action < ::Crumble::Turbo::Action
    controller do
      ctx.session.update!(__crumble_cookie_consented: consent)
      ctx.refresh_session_cookie if consent
    end

    policy do
      can_submit do
        !ctx.cookie_consent_chosen?
      end
    end

    def refresh_template
      Banner.new(ctx).turbo_stream.to_html(ctx.response)
    end

    abstract def consent : Bool
  end

  class AcceptAction < Action
    def consent : Bool
      true
    end
  end

  class DenyAction < Action
    def consent : Bool
      false
    end
  end
end
