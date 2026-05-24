class ApplicationController < ActionController::Base
  before_action :require_admin!
  helper_method :admin_signed_in?, :current_admin_email

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def require_admin!
    return if admin_signed_in?

    redirect_to sign_in_path
  end

  def admin_signed_in?
    current_admin_email.present?
  end

  def current_admin_email
    session[:admin_email].presence
  end

  def admin_email_allowed?(email)
    allowed_admin_emails.include?(email.to_s.downcase)
  end

  def allowed_admin_emails
    (ENV["ADMIN_USERS"].presence || ENV["ADMIN_USER"].presence || "wjr@wjr.us")
      .split(",")
      .map { |email| email.strip.downcase }
      .reject(&:blank?)
  end
end
